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

pub const Metadata = struct {
    artist: []const u8 = undefined,
    title: []const u8 = undefined,
};

const metadataContent = enum { @"xesam:title", @"xesam:artist", other };
const messageContent = enum { Metadata, PlaybackStatus, other };

fn getDictValue(dictKey: *dbus.MessageIter) !void {
    // Move to the value which is a variant
    _ = dbus.messageIterNext(dictKey);

    // Recurse into the variant
    var dictVariant: dbus.MessageIter = undefined;
    _ = dbus.messageIterRecurse(dictKey, &dictVariant);

    var variantContains = dbus.messageIterGetArgType(&dictVariant);

    var variantType = std.meta.intToEnum(dbus.BasicType, variantContains) catch dbus.BasicType.unknown;

    // TODO: Should probably look into handling more types.
    switch (variantType) {
        .string => {
            // The title is a string, so get it
            var dictVariantStr: [*:0]const u8 = undefined;
            _ = dbus.messageIterGetBasic(&dictVariant, @as(*void, @ptrCast(&dictVariantStr)));

            // And extract it
            var dictValueStr = try extractString(dictVariantStr);

            std.debug.print("{s}\n", .{dictValueStr});
        },
        .array => {

            // It contains an array, since media can have more than one artist.
            // Recurse into the array
            var artistArray: dbus.MessageIter = undefined;
            _ = dbus.messageIterRecurse(&dictVariant, &artistArray);

            // For simplicity we pick the first artist in the array.
            var artistString: [*:0]const u8 = undefined;
            _ = dbus.messageIterGetBasic(&artistArray, @as(*void, @ptrCast(&artistString)));

            // And extract it
            var contentStr = try extractString(artistString);

            std.debug.print("{s}\n", .{contentStr});
        },
        .unknown => {},
    }
}

fn unpackMetadata(messageIter: *dbus.MessageIter) !void {
    var result = Metadata{};
    // Move to the value of Metadata key
    _ = dbus.messageIterNext(messageIter);

    // Enter the variant
    var messageVariant: dbus.MessageIter = undefined;
    _ = dbus.messageIterRecurse(messageIter, &messageVariant);

    // Then the array
    var messageArray: dbus.MessageIter = undefined;
    _ = dbus.messageIterRecurse(&messageVariant, &messageArray);

    // Loop the array of dicts
    while (true) {
        // Move into the content key
        var dictKey: dbus.MessageIter = undefined;
        _ = dbus.messageIterRecurse(&messageArray, &dictKey);

        // Get the key
        var dictKeyVal: [*:0]const u8 = undefined;
        _ = dbus.messageIterGetBasic(&dictKey, @as(*void, @ptrCast(&dictKeyVal)));

        // Extract the metadata key
        var dictKeyStr = try extractString(dictKeyVal);

        // Match it to an enum
        var metadataCase = std.meta.stringToEnum(metadataContent, dictKeyStr) orelse metadataContent.other;

        switch (metadataCase) {
            .@"xesam:title" => {
                try getDictValue(&dictKey);
            },
            .@"xesam:artist" => {
                try getDictValue(&dictKey);
            },
            // All other metadata gets skipped
            .other => {},
        }

        // Break loop early in case we have picked up both fields
        if (result.artist.len > 0 and result.title.len > 0) {
            break;
        }

        // For safety, check if there is another item in the metadata array before proceeding to the next dict entry
        if (dbus.messageIterHasNext(&messageArray) == 1) {
            _ = dbus.messageIterNext(&messageArray);
        } else {
            // Otherwise break the loop
            break;
        }
    }
}

fn parseMessage(message: *dbus.MessageIter) !void {
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
                try unpackMetadata(&dictEntry);
            },
            .PlaybackStatus => {
                try getDictValue(&dictEntry);
            },
            .other => {},
        }
    }

    return;
}

fn messageHandler(connection: *dbus.Connection, message: *dbus.Message, user_data: *anyopaque) c_uint {
    _ = connection;
    _ = user_data;

    // Initialize the iter
    var iter: dbus.MessageIter = undefined;
    _ = dbus.messageIterInit(message, &iter);

    var parsedData = try parseMessage(&iter);
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
    var handler = dbus.busAddFilter(connection, messageHandler, null, null);
    _ = handler;
    while (dbus.connectionReadWriteDispatch(connection, 1000) != 0) {}
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
