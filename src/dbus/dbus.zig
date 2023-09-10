pub const bool_t = i32;
pub const size_t = u32;
pub const Error = extern struct {
    name: [*:0]const u8,
    message: [*:0]const u8,

    dummy_1: u32,
    dummy_2: u32,
    dummy_3: u32,
    dummy_4: u32,
    dummy_5: u32,

    padding1: *void,
};

const ErrorTypes = error{
    MethodCallFailed,
    SendMessageFailed
};

// Probably not idiomatic
pub const BasicType = enum(i32) {
    array = typeArray,
    string = typeString,
    invalid = typeInvalid,
};

pub const typeArray: i32 = 97;
pub const typeString: i32 = 115;
pub const typeInvalid: i32 = 0;


pub const MessageIter = extern struct {
    dummy1: *void,
    dummy2: *void,
    dummy3: u32,
    dummy4: i32,
    dummy5: i32,
    dummy6: i32,
    dummy7: i32,
    dummy8: i32,
    dummy9: i32,
    dummy10: i32,
    dummy11: i32,
    pad1: i32,
    pad2: *void,
    pad3: *void,
};

pub const Connection = opaque {};
pub const Message = opaque {};
pub const HandleMessageFunction = *const fn (*Connection, *Message, *anyopaque) void;
pub const FreeFunction = opaque {};

pub const BusType = enum(i32) {
    session = 0,
    system = 1,
    starter = 2,
    _,
};

extern fn dbus_connection_flush(connection: *Connection) void;
pub const connectionFlush = dbus_connection_flush;

extern fn dbus_connection_read_write_dispatch(connection: *Connection, timeout_ms: i32) bool_t;
pub const connectionReadWrite = dbus_connection_read_write;

pub extern fn dbus_connection_send_with_reply_and_block(
    connection: *Connection,
    message: *Message,
    timeout_ms: i32,
    err: *Error,
) ?*Message;
pub const connectionSendWithReplyAndBlock = dbus_connection_send_with_reply_and_block;

extern fn dbus_connection_read_write(connection: *Connection, timeout_ms: i32) bool_t;
pub const connectionReadWriteDispatch = dbus_connection_read_write_dispatch;

extern fn dbus_bus_get(bus_type: BusType, err: *Error) *Connection;
pub const busGet = dbus_bus_get;

extern fn dbus_bus_add_match(connection: *Connection, rule: [*:0]const u8, err: ?*Error) void;
pub const busAddMatch = dbus_bus_add_match;

extern fn dbus_connection_add_filter(connection: *Connection, function: HandleMessageFunction, user_data: ?*anyopaque, free_function: ?*FreeFunction) bool_t;
pub const busAddFilter = dbus_connection_add_filter;

extern fn dbus_error_init(err: *Error) void;
pub const errorInit = dbus_error_init;

extern fn dbus_error_is_set(err: *const Error) i32;
pub const errorIsSet = dbus_error_is_set;

extern fn dbus_message_append_args(message: *Message, first_arg_type: i32, ...) i32;
pub const messageAppendArgs = dbus_message_append_args;

extern fn dbus_message_get_sender(message: *Message) [*:0]const u8;
pub const messageGetSender = dbus_message_get_sender;

extern fn dbus_message_unref(message: *Message) void;
pub const messageUnref = dbus_message_unref;

extern fn dbus_bus_get_unique_name(connection: *Connection) [*:0]const u8;
pub const busGetUniqueName = dbus_bus_get_unique_name;

extern fn dbus_message_get_path(message: *Message) [*:0]const u8;
pub const messageGetPath = dbus_message_get_path;

extern fn dbus_message_get_signature(message: *Message) [*:0]const u8;
pub const messageGetSignature = dbus_message_get_signature;

extern fn dbus_message_is_signal(message: *Message, interface: [*:0]const u8, signal_name: [*:0]const u8) bool_t;
pub const messageIsSignal = dbus_message_is_signal;

extern fn dbus_message_new_method_call(
    destination: [*:0]const u8,
    path: [*:0]const u8,
    interface: [*:0]const u8,
    method: [*:0]const u8,
) ?*Message;
pub const messageNewMethodCall = dbus_message_new_method_call;

extern fn dbus_message_iter_init(message: *Message, iter: *MessageIter) i32;
pub const messageIterInit = dbus_message_iter_init;

extern fn dbus_message_iter_get_arg_type(iter: *MessageIter) i32;
pub const messageIterGetArgType = dbus_message_iter_get_arg_type;

extern fn dbus_message_iter_recurse(iter: *MessageIter, sub_iter: *MessageIter) void;
pub const messageIterRecurse = dbus_message_iter_recurse;

extern fn dbus_message_iter_get_basic(iter: *MessageIter, value: *void) void;
pub const messageIterGetBasic = dbus_message_iter_get_basic;

extern fn dbus_message_iter_init_append(query_message: *Message, iter: *MessageIter) void;
pub const messageIterInitAppend = dbus_message_iter_init_append;

extern fn dbus_message_iter_next(iter: *MessageIter) bool_t;
pub const messageIterNext = dbus_message_iter_next;

extern fn dbus_message_iter_get_signature(iter: *MessageIter) [*:0]const u8;
pub const messageIterGetSignature = dbus_message_iter_get_signature;

extern fn dbus_message_iter_has_next(iter: *MessageIter) bool_t;
pub const messageIterHasNext = dbus_message_iter_has_next;
