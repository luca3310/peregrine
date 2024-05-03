const std = @import("std");
const Allocator = std.mem.Allocator;

fn ListNode(comptime T: type) type {
    return struct {
        data: T,
        next: ?*ListNode(T),

        pub fn init(allocator: *Allocator, data: T) !*ListNode(T) {
            const node = try allocator.create(ListNode(T));
            node.* = ListNode(T){ .data = data, .next = null };
            return node;
        }
        pub fn deinit(self: *ListNode(T), allocator: *Allocator) void {
            allocator.free(self.data); // Free the dynamically allocated slice
        }
    };
}

pub fn List(comptime T: type) type {
    return struct {
        head: ?*ListNode(T) = null,
        alloc: Allocator,

        pub fn init(alloc: Allocator) List(T) {
            return List(T){ .alloc = alloc, .head = null };
        }

        pub fn deinit(self: *List(T)) void {
            var node = self.head;
            while (node) |current| {
                const next = current.next;
                current.deinit(&self.alloc); // Free the data before destroying the node
                self.alloc.destroy(current);
                node = next;
            }
        }

        pub fn append(self: *List(T), value: []const u8) !void {
            const mutableCopy = try self.alloc.alloc(u8, value.len);
            std.mem.copy(u8, mutableCopy, value);
            const newNode = try ListNode(T).init(&self.alloc, mutableCopy);
            if (self.head == null) {
                self.head = newNode;
            } else {
                var node = self.head;
                while (node.?.next) |next| {
                    node = next;
                }
                node.?.next = newNode;
            }
        }

        pub fn appendLineAtRow(self: *List(T), index: usize) !void {
            const emptyArray = try self.alloc.alloc(u8, 0); // Allocate an empty array
            const newNode = try ListNode(T).init(&self.alloc, emptyArray); // Create a new node with the empty array
            if (index == 0) { // Special case for inserting at the beginning
                newNode.next = self.head; // Point the new node to the current head
                self.head = newNode; // Update the head to be the new node
                return;
            }
            var node = self.head;
            var count: usize = 0;
            while (node) |current| {
                if (count + 1 == index) { // We want to insert after the current node
                    newNode.next = current.next; // Point the new node to the current node's next
                    current.next = newNode; // Insert the new node after the current node
                    return;
                }
                count += 1;
                node = current.next;
            }
            if (index > count) { // If index is out of bounds, deallocate and throw an error
                self.alloc.free(emptyArray);
                self.alloc.destroy(newNode);
                return error.IndexOutOfBounds;
            }
        }

        pub fn get(self: *List(T), index: usize) ?T {
            var count: usize = 0;
            var node = self.head;
            while (node) |current| {
                if (count == index) {
                    return current.data;
                }
                count += 1;
                node = current.next;
            }
            return null;
        }

        pub fn appendCharAtRowAndCol(self: *List(T), row: usize, col: usize, value: u8) !void {
            var count: usize = 0;
            var node = self.head;
            while (node) |current| { // Iterate through the nodes
                if (count == row) { // Found the correct row
                    const oldArray = current.data;
                    const newArrayLen = oldArray.len + 1;
                    const newArray = try self.alloc.alloc(u8, newArrayLen); // Allocate memory for the new array

                    std.mem.copy(u8, newArray[0..col], oldArray[0..col]);

                    newArray[col] = value;

                    if (col < oldArray.len) {
                        std.mem.copy(u8, newArray[col + 1 ..], oldArray[col..]);
                    }

                    self.alloc.free(oldArray); // Free the memory of the old array

                    current.data = newArray; // Update the node's data with the new array
                    break;
                }
                count += 1;
                node = current.next;
            }
        }

        pub fn removeCharAtRowAndCol(self: *List(T), row: usize, col: usize) !void {
            var count: usize = 0;
            var node = self.head;
            while (node) |current| {
                if (count == row) {
                    const oldArray = current.data;
                    const newArrayLen = oldArray.len - 1;
                    const newArray = try self.alloc.alloc(u8, newArrayLen); // Allocate memory for the new array

                    if (col > 0) {
                        std.mem.copy(u8, newArray[0..col], oldArray[0..col]);
                    }

                    if (col < oldArray.len - 1) {
                        std.mem.copy(u8, newArray[col..], oldArray[col + 1 ..]);
                    }

                    self.alloc.free(oldArray); // Free the memory of the old array

                    current.data = newArray; // Update the node's data with the new array
                    break;
                }
                count += 1;
                node = current.next;
            }
        }

        pub fn removeLineAtRow(self: *List(T), row: usize) !void {
            if (self.head == null) return error.LineDoesNotExist;

            // Special case for removing the head
            if (row == 0) {
                const tempNode = self.head.?;
                self.head = tempNode.next; // Update the head to the next node
                tempNode.deinit(&self.alloc); // Deallocate resources used by the head node
                self.alloc.destroy(tempNode);
                return;
            }

            var prevNode: ?*ListNode(T) = null;
            var currentNode = self.head;
            var count: usize = 0;

            while (currentNode) |node| {
                if (count == row) {
                    // If the node to remove is found
                    if (prevNode) |pNode| {
                        // Since prevNode is not null, safely dereference to modify its next
                        if (node.next) |nextNode| {
                            pNode.next = nextNode; // Direct linking to the next node
                        } else {
                            // If node to remove is the last, set prevNode's next to null
                            pNode.next = null;
                        }
                    } else {
                        // This should not happen since we handle the head separately
                        return error.UnexpectedNullPrevNode;
                    }
                    node.deinit(&self.alloc);
                    self.alloc.destroy(node);
                    return;
                }
                // Update prevNode and currentNode to traverse the list
                prevNode = currentNode;
                currentNode = node.next;
                count += 1;
            }

            // If we reach here, the specified row was out of bounds
            return error.LineDoesNotExist;
        }
    };
}
