const std = @import("std");
const debug = std.debug;
const term = @import("term");
const data = @import("data.zig");
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const os = std.os;

const ViewWindow = struct {
    startLine: u16,
    endLine: u16,
};

pub fn redraw(tty: *term.Term, myList: *data.List([]u8), viewWindow: ViewWindow) !void {
    // Clear the screen before redrawing
    tty.clearScreen();

    var currentLine: u16 = 0;
    var displayLine: u16 = 0; // This will be used to position lines on the screen from the top

    // Iterate through the list from the beginning
    var node = myList.head;
    while (node) |current| {
        // Check if the current line is within the view window
        if (currentLine >= viewWindow.startLine and currentLine <= viewWindow.endLine) {
            var lineNumBuf: [20]u8 = undefined;
            const lineNumStr = std.fmt.bufPrint(&lineNumBuf, "{} ", .{currentLine + 1}) catch unreachable;
            // If it is, display the line on the screen
            try tty.writeStringAt(4, displayLine, current.data);
            try tty.writeStringAt(0, displayLine, lineNumStr);
            displayLine += 1;
        }
        currentLine += 1;
        node = current.next;

        // Stop if we've reached the end of the view window
        if (currentLine > viewWindow.endLine) break;
    }

    // finish window with try tty.writeStringAt(0, displayLine, "~ ");
    while (displayLine <= viewWindow.endLine - viewWindow.startLine) {
        try tty.writeStringAt(0, displayLine, "~ ");
        displayLine += 1;
    }

    // Push the changes to the terminal
    try tty.update();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var tty = try term.Term.init(gpa.allocator());
    defer tty.deinit();

    const original = try os.tcgetattr(tty.ttyfile.handle);
    var raw = original;
    raw.lflag &= ~@as(
        os.linux.tcflag_t,
        os.linux.ECHO | os.linux.ICANON | os.linux.ISIG | os.linux.IEXTEN,
    );
    raw.iflag &= ~@as(
        os.linux.tcflag_t,
        os.linux.IXON | os.linux.ICRNL | os.linux.BRKINT | os.linux.INPCK | os.linux.ISTRIP,
    );
    raw.cc[os.system.V.TIME] = 0;
    raw.cc[os.system.V.MIN] = 1;
    try os.tcsetattr(tty.ttyfile.handle, .FLUSH, raw);

    var viewWindow = ViewWindow{ .startLine = 0, .endLine = 40 }; // N needs to be defined based on your terminal size or a fixed value

    const alloc = gpa.allocator();

    var myList = data.List([]u8).init(alloc);
    defer myList.deinit();

    try myList.appendLineAtRow(0);

    try redraw(&tty, &myList, viewWindow);

    tty.setCursor(4, 0);

    try tty.update(); // Update the terminal with any changes
    // Now, enter the main event loop
    while (true) {
        var buffer: [1]u8 = undefined;
        _ = try tty.ttyfile.read(&buffer);
        if (buffer[0] == '\x1B') {
            raw.cc[os.system.V.TIME] = 1;
            raw.cc[os.system.V.MIN] = 0;
            try os.tcsetattr(tty.ttyfile.handle, .NOW, raw);

            var esc_buffer: [8]u8 = undefined;
            const esc_read = try tty.ttyfile.read(&esc_buffer);

            raw.cc[os.system.V.TIME] = 0;
            raw.cc[os.system.V.MIN] = 1;
            try os.tcsetattr(tty.ttyfile.handle, .NOW, raw);

            if (esc_read == 0) {
                try os.tcsetattr(tty.ttyfile.handle, .FLUSH, original);
                return;
            }
            if (esc_read >= 2) {
                var x: u16 = 0;
                var y: u16 = 0;
                tty.getCursor(&x, &y);
                switch (esc_buffer[1]) {
                    'A' => {
                        // Up arrow key pressed
                        if (y > 0) {
                            if (myList.get(y + viewWindow.startLine - 1)) |line2| {
                                var length: u16 = @truncate(line2.len + 4);
                                if (myList.get(y + viewWindow.startLine)) |line3| {
                                    var length2: u16 = @truncate(line3.len + 4);
                                    _ = length2;
                                    tty.setCursor(length, y - 1); // Adjust cursor position after removing a line
                                }
                            }
                        } else if (viewWindow.startLine > 0 and y + viewWindow.startLine == viewWindow.startLine) {
                            viewWindow.startLine -= 1;
                            viewWindow.endLine -= 1;

                            try redraw(&tty, &myList, viewWindow);
                            if (myList.get(y + viewWindow.startLine - 1)) |line2| {
                                var length: u16 = @truncate(line2.len + 4);

                                tty.setCursor(length, y); // Adjust cursor position after removing a line
                            }
                        }
                    },
                    'B' => {
                        const currentLineInView = y + viewWindow.startLine; // Calculate the actual line number in the document
                        const nextLineIndex = currentLineInView + 1; // Determine the next line's index

                        // Check if there's a next line in the document
                        if (myList.get(nextLineIndex) != null) {
                            if (y < viewWindow.endLine - viewWindow.startLine) {
                                // If the next line is within the view window, simply move the cursor down
                                tty.setCursor(4, y + 1);
                            } else {
                                // If we're at the bottom of the view window, scroll the window down
                                viewWindow.startLine += 1;
                                viewWindow.endLine += 1;

                                // Redraw the screen with the updated view window
                                try redraw(&tty, &myList, viewWindow);

                                // Optionally, adjust cursor position if needed. For example, you might
                                // want to keep the cursor at the bottom of the window or move it to the top.
                                // Here, we're keeping the cursor at the bottom of the window:
                                tty.setCursor(4, y); // Adjust as needed based on your UI behavior
                            }
                        }
                    },
                    'C' => {
                        // Right arrow key pressed
                        if (myList.get(y + viewWindow.startLine)) |line| {
                            if (x < (line.len + 4)) { // Ensure not to go past the line end
                                tty.setCursor(x + 1, y);
                            }
                        }
                    },
                    'D' => {
                        // Left arrow key pressed
                        if (x > 4) { // Check to ensure cursor doesn't move into the prefix area
                            tty.setCursor(x - 1, y);
                        }
                    },
                    else => {},
                }
            }
        } else if (buffer[0] == '\n' or buffer[0] == '\r') {
            var x: u16 = 0;
            var y: u16 = 0;
            tty.getCursor(&x, &y);

            try tty.hideCursor();
            try myList.appendLineAtRow(y + 1);
            if (y + viewWindow.startLine == viewWindow.endLine) {
                viewWindow.startLine += 1;
                viewWindow.endLine += 1;

                try redraw(&tty, &myList, viewWindow);
                tty.setCursor(4, y);
            } else {
                try redraw(&tty, &myList, viewWindow);
                tty.setCursor(4, y + 1);
            }

            try tty.showCursor();
        } else if (buffer[0] == 0x08 or buffer[0] == 0x7F) { // Check for backspace or delete
            var x: u16 = 0;
            var y: u16 = 0;
            tty.getCursor(&x, &y);

            // Check to ensure we're not at the start of a line to avoid underflow
            if (x > 4) {
                // Remove the character from the data structure at the current line and one character behind the cursor
                try myList.removeCharAtRowAndCol(y + viewWindow.startLine, x - 5); // Adjust index as needed based on your data structure's indexing

                try tty.hideCursor();

                try tty.clearCurrentLineRaw();
                var selectedArray: ?[]u8 = myList.get(y + viewWindow.startLine); // Assuming this method exists and returns the updated line
                if (selectedArray != null) {
                    const selectedArrayValue = selectedArray.?;
                    var lineNumBuf: [20]u8 = undefined;
                    const lineNumStr = std.fmt.bufPrint(&lineNumBuf, "{} ", .{y + viewWindow.startLine + 1}) catch unreachable;

                    try tty.writeStringAt(0, y, lineNumStr);
                    try tty.writeStringAt(4, y, @as([]u8, selectedArrayValue)); // Rewrite the modified line
                }

                tty.setCursor(x - 1, y); // Move the cursor back
                try tty.showCursor();
                // Move the cursor back one space
            } else if (myList.get(y + viewWindow.startLine)) |line| {
                if (line.len == 0 and y > 0) {
                    tty.setCursor(x, y - 1);
                    // Remove the line from the list
                    try myList.removeLineAtRow(y + viewWindow.startLine);
                    // Optionally, adjust the view window if necessary
                    // Redraw the screen to reflect the list changes
                    try redraw(&tty, &myList, viewWindow);
                    if (myList.get(y + viewWindow.startLine - 1)) |line2| {
                        var length: u16 = @truncate(line2.len + 4);

                        tty.setCursor(length, y - 1); // Adjust cursor position after removing a line
                    }
                }
            }
        } else if (buffer[0] <= 0x7F) {
            var x: u16 = 0;
            var y: u16 = 0;
            tty.getCursor(&x, &y);
            // Append the encoded bytes to the list
            try myList.appendCharAtRowAndCol(y + viewWindow.startLine, x - 4, buffer[0]);
            try tty.hideCursor();
            try tty.clearCurrentLineRaw();
            var selectedArray: ?[]u8 = myList.get(y + viewWindow.startLine); // Assuming this method exists and returns the updated line
            if (selectedArray != null) {
                const selectedArrayValue = selectedArray.?;
                var lineNumBuf: [20]u8 = undefined;
                const lineNumStr = std.fmt.bufPrint(&lineNumBuf, "{} ", .{y + viewWindow.startLine + 1}) catch unreachable;

                try tty.writeStringAt(0, y, lineNumStr);
                try tty.writeStringAt(4, y, @as([]u8, selectedArrayValue)); // Rewrite the modified line
            }

            tty.setCursor(x + 1, y);
            try tty.showCursor();
        }
        try tty.update(); // Update the terminal with any changes
    }
}
