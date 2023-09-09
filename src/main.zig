const std = @import("std");
const dbus = @import("dbus/dbus.zig");

fn extractString(ptr: [*]const u8) ![]const u8 {
    const nullTerminator: u8 = 0;

    var endIndex: usize = 0;
    while (ptr[endIndex] != nullTerminator) {
        endIndex += 1;
    }

    const slice = ptr[0..endIndex];
    return slice;
}

pub const Media = struct {
    artist: []const u8 = undefined,
    title: []const u8 = undefined,
};

const metadataContent = enum { @"xesam:title", @"xesam:artist", other };
const messageContent = enum { Metadata, PlaybackStatus, other };

fn extractDBusMetadata(message: *dbus.MessageIter) !void {
    var result = Media{};
    // Skip the first string in the message, which is the sender interface
    _ = dbus.messageIterNext(message);

    // Guard to make sure we are not try to move into an empty array.
    if (dbus.messageIterHasNext(message) == 1) {
        // This is the first array containing the dict
        // The key tells us which contents are in it
        var variant: dbus.MessageIter = undefined;
        _ = dbus.messageIterRecurse(message, &variant);

        // Get the dict key
        var dictEntry: dbus.MessageIter = undefined;
        _ = dbus.messageIterRecurse(&variant, &dictEntry);

        // This should now be a string telling us about the contents
        var keyStr: [*:0]const u8 = undefined;
        _ = dbus.messageIterGetBasic(&dictEntry, @as(*void, @ptrCast(&keyStr)));

        // Extract the string
        var extractedKeyStr = try extractString(keyStr);

        var contentCase = std.meta.stringToEnum(messageContent, extractedKeyStr) orelse messageContent.other;

        switch (contentCase) {
            .Metadata => {

                // Move to the value of Metadata key
                _ = dbus.messageIterNext(&dictEntry);

                // Enter the variant
                var contents: dbus.MessageIter = undefined;
                _ = dbus.messageIterRecurse(&dictEntry, &contents);

                // Then the array
                var contentEntry: dbus.MessageIter = undefined;
                _ = dbus.messageIterRecurse(&contents, &contentEntry);

                // Loop the array of dicts
                while (true) {
                    // Move into the content key
                    var contentKey: dbus.MessageIter = undefined;
                    _ = dbus.messageIterRecurse(&contentEntry, &contentKey);

                    // Get the key
                    var contentKeyVal: [*:0]const u8 = undefined;
                    _ = dbus.messageIterGetBasic(&contentKey, @as(*void, @ptrCast(&contentKeyVal)));

                    // Extract the metadata key
                    var contentKeyStr = try extractString(contentKeyVal);

                    var metadataCase = std.meta.stringToEnum(metadataContent, contentKeyStr) orelse metadataContent.other;

                    switch (metadataCase) {
                        .@"xesam:title" => {
                            // Move to the value which is a variant
                            _ = dbus.messageIterNext(&contentKey);

                            // Recurse into the variant
                            var contentsVariant: dbus.MessageIter = undefined;
                            _ = dbus.messageIterRecurse(&contentKey, &contentsVariant);

                            // The title is a string, so get it
                            var contentString: [*:0]const u8 = undefined;
                            _ = dbus.messageIterGetBasic(&contentsVariant, @as(*void, @ptrCast(&contentString)));

                            // And extract it
                            var contentStr = try extractString(contentString);

                            result.title = contentStr;
                            std.debug.print("{s}\n", .{result.title});
                        },
                        .@"xesam:artist" => {
                            // Move to the value which is a variant
                            _ = dbus.messageIterNext(&contentKey);

                            // Recurse into the variant
                            var contentsVariant: dbus.MessageIter = undefined;
                            _ = dbus.messageIterRecurse(&contentKey, &contentsVariant);

                            // It contains an array, since media can have more than one artist.
                            // Recurse into the array
                            var artistArray: dbus.MessageIter = undefined;
                            _ = dbus.messageIterRecurse(&contentsVariant, &artistArray);

                            // For simplicity we pick the first artist in the array.
                            var artistString: [*:0]const u8 = undefined;
                            _ = dbus.messageIterGetBasic(&artistArray, @as(*void, @ptrCast(&artistString)));

                            // And extract it
                            var contentStr = try extractString(artistString);

                            result.artist = contentStr;
                            std.debug.print("{s}\n", .{result.artist});
                        },
                        // All other metadata gets skipped
                        .other => {},
                    }

                    // Break loop early in case we have picked up both fields
                    if (result.artist.len > 0 and result.title.len > 0) {
                        break;
                    }

                    // For safety, check if there is another item in the metadata array before proceeding to the next dict entry
                    if (dbus.messageIterHasNext(&contentEntry) == 1) {
                        _ = dbus.messageIterNext(&contentEntry);
                    } else {
                        // Otherwise break the loop
                        break;
                    }
                }
            },
            .PlaybackStatus => {
                // Move to the value of the key
                _ = dbus.messageIterNext(&dictEntry);

                // Enter the variant which is a string containing the status
                var contents: dbus.MessageIter = undefined;
                _ = dbus.messageIterRecurse(&dictEntry, &contents);

                // Get the string
                var playbackstatus: [*:0]const u8 = undefined;
                _ = dbus.messageIterGetBasic(&contents, @as(*void, @ptrCast(&playbackstatus)));

                // And extract it
                var statusString = try extractString(playbackstatus);

                std.debug.print("{s}\n", .{statusString});
            },
            .other => {},
        }
    }

    return;
}

fn properties_changed_handler(connection: *dbus.Connection, message: *dbus.Message, user_data: *anyopaque) c_uint {
    _ = connection;
    _ = user_data;

    // Initialize the iter
    var iter: dbus.MessageIter = undefined;
    _ = dbus.messageIterInit(message, &iter);

    var parsedData = try extractDBusMetadata(&iter);
    _ = parsedData;

    return 0;
}

pub fn main() !void {
    var err: dbus.Error = undefined;
    dbus.errorInit(&err);
    var connection: *dbus.Connection = dbus.busGet(dbus.BusType.session, &err);
    const PROPERTIES_CHANGED_MATCH = "interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path='/org/mpris/MediaPlayer2'";
    dbus.busAddMatch(connection, PROPERTIES_CHANGED_MATCH, &err);
    dbus.connectionFlush(connection);
    var handler = dbus.busAddFilter(connection, properties_changed_handler, null, null);
    _ = handler;
    while (dbus.connectionReadWriteDispatch(connection, 1000) != 0) {}
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
