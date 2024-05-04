const std = @import("std");
const DoublyLinkedList = std.DoublyLinkedList;

/// AtomicQueue is an extremely basic queue/channel thread-safe implementation.
/// Nodes are NOT owned by the queue.
pub fn AtomicQueue(comptime T: type) type {
    return struct {
        l: DoublyLinkedList(T),
        mutex: std.Thread.Mutex,
        size: u32,

        const Self = @This();
        pub const Node = DoublyLinkedList(T).Node;

        /// init creates an AtomicQueue.
        pub fn init() Self {
            return .{
                .l = DoublyLinkedList(T){},
                .mutex = std.Thread.Mutex{},
                .size = 0,
            };
        }

        /// isEmpty returns if the queue is empty.
        pub fn isEmpty(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.size == 0;
        }

        /// put puts a new entry in the queue.
        pub fn put(self: *Self, v: *Node) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.size += 1;

            self.l.append(v);
        }

        /// get returns the oldest message pushed into the queue.
        pub fn get(self: *Self) ?*Node {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.size == 0) {
                return null;
            }

            self.size -= 1;

            return self.l.popFirst();
        }
    };
}
