const std = @import("std");
const dbus = @import("dbus/dbus.zig");
const String = @import("zig_string").String;

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

/// Ask DBus for the nameowner (ID) of an interface
fn queryId(connection: *dbus.Connection, mediaplayer: []const u8) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var name = String.init_with_contents(arena.allocator(), "org.mpris.MediaPlayer2.") catch |err| {
        std.log.err("Initializing string for ID query failed.", .{});
        return err;
    };
    defer name.deinit();

    name.concat(mediaplayer) catch |err| {
        std.log.err("Appending the mediaplayer to argument for ID query failed.", .{});
        return err;
    };
    var argument = name.toOwned();

    var err: dbus.Error = undefined;
    dbus.errorInit(&err);

    var query_message: *dbus.Message = dbus.messageNewMethodCall(
        "org.freedesktop.DBus",
        "/",
        "org.freedesktop.DBus",
        "GetNameOwner",
    ) orelse {
        const error_message = if (dbus.errorIsSet(&err) != 0) err.message else "unknown";
        std.log.err("dbus_client: dbus_message_new_method_call failed. Error: {s}", .{error_message});
        return error.MethodCallFailed;
    };

    var argument_type = dbus.typeString;
    _ = dbus.messageAppendArgs(query_message, argument_type, &argument, dbus.typeInvalid);

    var reply_message: *dbus.Message = dbus.connectionSendWithReplyAndBlock(
        connection,
        query_message,
        1000,
        &err,
    ) orelse {
        const error_message = if (dbus.errorIsSet(&err) != 0) err.message else "unknown";
        std.log.err("dbus_client: dbus.connectionSendWithReplyAndBlock failed. Error: {s}", .{error_message});
        return error.SendMessageFailed;
    };

    dbus.messageUnref(query_message);

    var iter: dbus.MessageIter = undefined;

    // Initialize iter of the reply
    _ = dbus.messageIterInit(reply_message, &iter);

    // The reply is a string, so we can pull it directly
    var id: [*:0]const u8 = undefined;
    dbus.messageIterGetBasic(&iter, @as(*void, @ptrCast(&id)));

    var idString = try extractString(id);

    std.debug.print("ID from query: {s}\n", .{idString});
    return idString;
}

/// Ask for a given property of the mediaplayer, e.g. metadata fields or playbackstatus
fn getProperty(comptime T: type, connection: *dbus.Connection) !void {
    var err: dbus.Error = undefined;
    dbus.errorInit(&err);

    var query_message: *dbus.Message = dbus.messageNewMethodCall(
        "org.mpris.MediaPlayer2.spotify",
        "/org/mpris/MediaPlayer2",
        "org.freedesktop.DBus.Properties",
        "Get",
    ) orelse {
        std.log.err("dbus_client: dbus_message_new_method_call failed.", .{});
        return;
    };

    const arg1 = "org.mpris.MediaPlayer2.Player";
    const arg2 = "PlaybackStatus";

    _ = dbus.messageAppendArgs(query_message, dbus.typeString, &arg1, dbus.typeString, &arg2, dbus.typeInvalid);

    var reply_message: *dbus.Message = dbus.connectionSendWithReplyAndBlock(
        connection,
        query_message,
        1000,
        &err,
    ) orelse {
        std.log.err("dbus_client: dbus.connectionSendWithReplyAndBlock failed. Error", .{});
        return;
    };

    dbus.messageUnref(query_message);

    var iter: dbus.MessageIter = undefined;
    var sub: dbus.MessageIter = undefined;

    _ = dbus.messageIterInit(reply_message, &iter);

    dbus.messageIterRecurse(&iter, &sub);

    var result: T = undefined;
    dbus.messageIterGetBasic(&sub, @as(*void, @ptrCast(&result)));
    dbus.messageUnref(reply_message);

    std.debug.print("Response: {s}", .{result});
    //return result;
}

/// Get the dict value from a MessageIter depending on the type within.
fn getDictValue(dictKey: *dbus.MessageIter) !void {
    // Move to the value which is a variant
    _ = dbus.messageIterNext(dictKey);

    // Recurse into the variant
    var dictVariant: dbus.MessageIter = undefined;
    _ = dbus.messageIterRecurse(dictKey, &dictVariant);

    var variantContains = dbus.messageIterGetArgType(&dictVariant);

    // TODO: This should error rather than setting type to invalid.
    var variantType = std.meta.intToEnum(dbus.BasicType, variantContains) catch dbus.BasicType.invalid;

    // TODO: Could probably look into handling more types.
    switch (variantType) {
        .string => {
            // Go right for the string
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
        else => {},
    }
}

/// Unpack metadata from a picked up message
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

/// Parse message that is picked up.
fn parseMessage(connection: *dbus.Connection, message: *dbus.Message) !void {

    // Get the sender ID of the message received.
    var sender = dbus.messageGetSender(message);
    var senderId = extractString(sender) catch {
        std.log.err("Failed to extract the sender ID from a message.", .{});
        return;
    };

    var mediaplayerId = queryId(connection, "spotify") catch {
        std.log.err("Failed to get the mediaplayer ID from DBus.", .{});
        return;
    };

    // Guard to see that the message received is actually the mediaplayer of interest
    if (!std.mem.eql(u8, senderId, mediaplayerId)) {
        return;
    }

    // Initialize the iter
    var iter: dbus.MessageIter = undefined;
    _ = dbus.messageIterInit(message, &iter);

    // Skip the first string in the message, which is the sender interface
    _ = dbus.messageIterNext(&iter);

    // Guard to make sure we are not try to move into an empty array.
    if (dbus.messageIterHasNext(&iter) == 1) {
        // This is the first array containing the dict
        // The key tells us which contents are in it
        var variant: dbus.MessageIter = undefined;
        _ = dbus.messageIterRecurse(&iter, &variant);

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
                try getProperty([*:0]const u8, connection);
            },
            .PlaybackStatus => {
                try getDictValue(&dictEntry);
            },
            .other => {},
        }
    }

    return;
}

/// The message handler for messages that are picked up.
fn messageHandler(connection: *dbus.Connection, message: *dbus.Message, user_data: *anyopaque) void {
    _ = user_data;

    // TODO: This needs to be handled.
    var parsedData = parseMessage(connection, message) catch return;
    _ = parsedData;

    return;
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
