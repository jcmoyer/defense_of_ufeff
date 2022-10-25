//! Minimal SDL2 bindings
//!
//! Goals:
//!
//! - Only bind what we need
//! - Do not try to make things "prettier" than they are in C
//!   Some concepts like C enums don't translate well to zig (see also:
//!   https://github.com/ziglang/zig/issues/2115#issuecomment-827968279)
//!
//! Maybe there is room for higher level bindings for zig, but in my opinion
//! it's easier to work with the more familiar C API.

pub const SDL_INIT_TIMER = 0x00000001;
pub const SDL_INIT_AUDIO = 0x00000010;
pub const SDL_INIT_VIDEO = 0x00000020;
pub const SDL_INIT_JOYSTICK = 0x00000200;
pub const SDL_INIT_HAPTIC = 0x00001000;
pub const SDL_INIT_GAMECONTROLLER = 0x00002000;
pub const SDL_INIT_EVENTS = 0x00004000;
pub const SDL_INIT_SENSOR = 0x00008000;
pub const SDL_INIT_NOPARACHUTE = 0x00100000;
pub const SDL_INIT_EVERYTHING = (SDL_INIT_TIMER | SDL_INIT_AUDIO | SDL_INIT_VIDEO | SDL_INIT_EVENTS |
    SDL_INIT_JOYSTICK | SDL_INIT_HAPTIC | SDL_INIT_GAMECONTROLLER | SDL_INIT_SENSOR);

pub extern fn SDL_Init(flags: u32) c_int;
pub extern fn SDL_Quit() void;

pub const SDL_Window = opaque {};
pub extern fn SDL_CreateWindow(title: [*:0]const u8, x: c_int, y: c_int, w: c_int, h: c_int, flags: u32) ?*SDL_Window;
// Can take a null window, but sets SDL last error
pub extern fn SDL_DestroyWindow(window: ?*SDL_Window) void;
pub extern fn SDL_GetWindowSize(window: *SDL_Window, w: ?*c_int, h: ?*c_int) void;

pub extern fn SDL_GetError() [*:0]const u8;

// window pos
pub const SDL_WINDOWPOS_CENTERED_MASK = 0x2FFF0000;
pub fn SDL_WINDOWPOS_CENTERED_DISPLAY(comptime x: comptime_int) comptime_int {
    return SDL_WINDOWPOS_CENTERED_MASK | x;
}
pub const SDL_WINDOWPOS_CENTERED = SDL_WINDOWPOS_CENTERED_DISPLAY(0);

//#define SDL_WINDOWPOS_ISCENTERED(X)    \
//            (((X)&0xFFFF0000) == SDL_WINDOWPOS_CENTERED_MASK)

// window flags
pub const SDL_WINDOW_FULLSCREEN = 0x00000001;
pub const SDL_WINDOW_OPENGL = 0x00000002;
pub const SDL_WINDOW_SHOWN = 0x00000004;
pub const SDL_WINDOW_HIDDEN = 0x00000008;
pub const SDL_WINDOW_BORDERLESS = 0x00000010;
pub const SDL_WINDOW_RESIZABLE = 0x00000020;
pub const SDL_WINDOW_MINIMIZED = 0x00000040;
pub const SDL_WINDOW_MAXIMIZED = 0x00000080;
pub const SDL_WINDOW_MOUSE_GRABBED = 0x00000100;
pub const SDL_WINDOW_INPUT_FOCUS = 0x00000200;
pub const SDL_WINDOW_MOUSE_FOCUS = 0x00000400;
pub const SDL_WINDOW_FULLSCREEN_DESKTOP = (SDL_WINDOW_FULLSCREEN | 0x00001000);
pub const SDL_WINDOW_FOREIGN = 0x00000800;
pub const SDL_WINDOW_ALLOW_HIGHDPI = 0x00002000;

pub const SDL_WINDOW_MOUSE_CAPTURE = 0x00004000;
pub const SDL_WINDOW_ALWAYS_ON_TOP = 0x00008000;
pub const SDL_WINDOW_SKIP_TASKBAR = 0x00010000;
pub const SDL_WINDOW_UTILITY = 0x00020000;
pub const SDL_WINDOW_TOOLTIP = 0x00040000;
pub const SDL_WINDOW_POPUP_MENU = 0x00080000;
pub const SDL_WINDOW_KEYBOARD_GRABBED = 0x00100000;
pub const SDL_WINDOW_VULKAN = 0x10000000;
pub const SDL_WINDOW_METAL = 0x20000000;

pub const SDL_WINDOW_INPUT_GRABBED = SDL_WINDOW_MOUSE_GRABBED;

// events
// we use an enum here because the original definition relies on count-up behavior
const SDL_EventType = enum(c_int) {
    SDL_FIRSTEVENT = 0,
    SDL_QUIT = 0x100,
    SDL_APP_TERMINATING,
    SDL_APP_LOWMEMORY,
    SDL_APP_WILLENTERBACKGROUND,
    SDL_APP_DIDENTERBACKGROUND,
    SDL_APP_WILLENTERFOREGROUND,
    SDL_APP_DIDENTERFOREGROUND,
    SDL_LOCALECHANGED,
    SDL_DISPLAYEVENT = 0x150,
    SDL_WINDOWEVENT = 0x200,
    SDL_SYSWMEVENT,
    SDL_KEYDOWN = 0x300,
    SDL_KEYUP,
    SDL_TEXTEDITING,
    SDL_TEXTINPUT,
    SDL_KEYMAPCHANGED,
    SDL_TEXTEDITING_EXT,
    SDL_MOUSEMOTION = 0x400,
    SDL_MOUSEBUTTONDOWN,
    SDL_MOUSEBUTTONUP,
    SDL_MOUSEWHEEL,
    SDL_JOYAXISMOTION = 0x600,
    SDL_JOYBALLMOTION,
    SDL_JOYHATMOTION,
    SDL_JOYBUTTONDOWN,
    SDL_JOYBUTTONUP,
    SDL_JOYDEVICEADDED,
    SDL_JOYDEVICEREMOVED,
    SDL_JOYBATTERYUPDATED,
    SDL_CONTROLLERAXISMOTION = 0x650,
    SDL_CONTROLLERBUTTONDOWN,
    SDL_CONTROLLERBUTTONUP,
    SDL_CONTROLLERDEVICEADDED,
    SDL_CONTROLLERDEVICEREMOVED,
    SDL_CONTROLLERDEVICEREMAPPED,
    SDL_CONTROLLERTOUCHPADDOWN,
    SDL_CONTROLLERTOUCHPADMOTION,
    SDL_CONTROLLERTOUCHPADUP,
    SDL_CONTROLLERSENSORUPDATE,
    SDL_FINGERDOWN = 0x700,
    SDL_FINGERUP,
    SDL_FINGERMOTION,
    SDL_DOLLARGESTURE = 0x800,
    SDL_DOLLARRECORD,
    SDL_MULTIGESTURE,
    SDL_CLIPBOARDUPDATE = 0x900,
    SDL_DROPFILE = 0x1000,
    SDL_DROPTEXT,
    SDL_DROPBEGIN,
    SDL_DROPCOMPLETE,
    SDL_AUDIODEVICEADDED = 0x1100,
    SDL_AUDIODEVICEREMOVED,
    SDL_SENSORUPDATE = 0x1200,
    SDL_RENDER_TARGETS_RESET = 0x2000,
    SDL_RENDER_DEVICE_RESET,
    SDL_POLLSENTINEL = 0x7F00,
    SDL_USEREVENT = 0x8000,
    SDL_LASTEVENT = 0xFFFF,
};

// **
//  *  \brief Fields shared by every event
//  */
// typedef struct SDL_CommonEvent
// {
//     Uint32 type;
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
// } SDL_CommonEvent;

// /**
//  *  \brief Display state change event data (event.display.*)
//  */
// typedef struct SDL_DisplayEvent
// {
//     Uint32 type;        /**< ::SDL_DISPLAYEVENT */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
//     Uint32 display;     /**< The associated display index */
//     Uint8 event;        /**< ::SDL_DisplayEventID */
//     Uint8 padding1;
//     Uint8 padding2;
//     Uint8 padding3;
//     Sint32 data1;       /**< event dependent data */
// } SDL_DisplayEvent;

// /**
//  *  \brief Window state change event data (event.window.*)
//  */
// typedef struct SDL_WindowEvent
// {
//     Uint32 type;        /**< ::SDL_WINDOWEVENT */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
//     Uint32 windowID;    /**< The associated window */
//     Uint8 event;        /**< ::SDL_WindowEventID */
//     Uint8 padding1;
//     Uint8 padding2;
//     Uint8 padding3;
//     Sint32 data1;       /**< event dependent data */
//     Sint32 data2;       /**< event dependent data */
// } SDL_WindowEvent;

pub const SDL_KeyboardEvent = extern struct {
    type: SDL_EventType,
    timestamp: u32,
    windowID: u32,
    state: u8,
    repeat: u8,
    padding2: u8,
    padding3: u8,
    keysym: SDL_Keysym,
};

// #define SDL_TEXTEDITINGEVENT_TEXT_SIZE (32)
// /**
//  *  \brief Keyboard text editing event structure (event.edit.*)
//  */
// typedef struct SDL_TextEditingEvent
// {
//     Uint32 type;                                /**< ::SDL_TEXTEDITING */
//     Uint32 timestamp;                           /**< In milliseconds, populated using SDL_GetTicks() */
//     Uint32 windowID;                            /**< The window with keyboard focus, if any */
//     char text[SDL_TEXTEDITINGEVENT_TEXT_SIZE];  /**< The editing text */
//     Sint32 start;                               /**< The start cursor of selected editing text */
//     Sint32 length;                              /**< The length of selected editing text */
// } SDL_TextEditingEvent;

// /**
//  *  \brief Extended keyboard text editing event structure (event.editExt.*) when text would be
//  *  truncated if stored in the text buffer SDL_TextEditingEvent
//  */
// typedef struct SDL_TextEditingExtEvent
// {
//     Uint32 type;                                /**< ::SDL_TEXTEDITING_EXT */
//     Uint32 timestamp;                           /**< In milliseconds, populated using SDL_GetTicks() */
//     Uint32 windowID;                            /**< The window with keyboard focus, if any */
//     char* text;                                 /**< The editing text, which should be freed with SDL_free(), and will not be NULL */
//     Sint32 start;                               /**< The start cursor of selected editing text */
//     Sint32 length;                              /**< The length of selected editing text */
// } SDL_TextEditingExtEvent;

// #define SDL_TEXTINPUTEVENT_TEXT_SIZE (32)
// /**
//  *  \brief Keyboard text input event structure (event.text.*)
//  */
// typedef struct SDL_TextInputEvent
// {
//     Uint32 type;                              /**< ::SDL_TEXTINPUT */
//     Uint32 timestamp;                         /**< In milliseconds, populated using SDL_GetTicks() */
//     Uint32 windowID;                          /**< The window with keyboard focus, if any */
//     char text[SDL_TEXTINPUTEVENT_TEXT_SIZE];  /**< The input text */
// } SDL_TextInputEvent;

pub const SDL_MouseMotionEvent = extern struct {
    type: u32,
    timestamp: u32,
    windowID: u32,
    which: u32,
    state: u32,
    x: i32,
    y: i32,
    xrel: i32,
    yrel: i32,
};

// /**
//  *  \brief Mouse button event structure (event.button.*)
//  */
// typedef struct SDL_MouseButtonEvent
// {
//     Uint32 type;        /**< ::SDL_MOUSEBUTTONDOWN or ::SDL_MOUSEBUTTONUP */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
//     Uint32 windowID;    /**< The window with mouse focus, if any */
//     Uint32 which;       /**< The mouse instance id, or SDL_TOUCH_MOUSEID */
//     Uint8 button;       /**< The mouse button index */
//     Uint8 state;        /**< ::SDL_PRESSED or ::SDL_RELEASED */
//     Uint8 clicks;       /**< 1 for single-click, 2 for double-click, etc. */
//     Uint8 padding1;
//     Sint32 x;           /**< X coordinate, relative to window */
//     Sint32 y;           /**< Y coordinate, relative to window */
// } SDL_MouseButtonEvent;

// /**
//  *  \brief Mouse wheel event structure (event.wheel.*)
//  */
// typedef struct SDL_MouseWheelEvent
// {
//     Uint32 type;        /**< ::SDL_MOUSEWHEEL */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
//     Uint32 windowID;    /**< The window with mouse focus, if any */
//     Uint32 which;       /**< The mouse instance id, or SDL_TOUCH_MOUSEID */
//     Sint32 x;           /**< The amount scrolled horizontally, positive to the right and negative to the left */
//     Sint32 y;           /**< The amount scrolled vertically, positive away from the user and negative toward the user */
//     Uint32 direction;   /**< Set to one of the SDL_MOUSEWHEEL_* defines. When FLIPPED the values in X and Y will be opposite. Multiply by -1 to change them back */
//     float preciseX;     /**< The amount scrolled horizontally, positive to the right and negative to the left, with float precision (added in 2.0.18) */
//     float preciseY;     /**< The amount scrolled vertically, positive away from the user and negative toward the user, with float precision (added in 2.0.18) */
//     Sint32 mouseX;      /**< X coordinate, relative to window (added in 2.26.0) */
//     Sint32 mouseY;      /**< Y coordinate, relative to window (added in 2.26.0) */
// } SDL_MouseWheelEvent;

// /**
//  *  \brief Joystick axis motion event structure (event.jaxis.*)
//  */
// typedef struct SDL_JoyAxisEvent
// {
//     Uint32 type;        /**< ::SDL_JOYAXISMOTION */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
//     SDL_JoystickID which; /**< The joystick instance id */
//     Uint8 axis;         /**< The joystick axis index */
//     Uint8 padding1;
//     Uint8 padding2;
//     Uint8 padding3;
//     Sint16 value;       /**< The axis value (range: -32768 to 32767) */
//     Uint16 padding4;
// } SDL_JoyAxisEvent;

// /**
//  *  \brief Joystick trackball motion event structure (event.jball.*)
//  */
// typedef struct SDL_JoyBallEvent
// {
//     Uint32 type;        /**< ::SDL_JOYBALLMOTION */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
//     SDL_JoystickID which; /**< The joystick instance id */
//     Uint8 ball;         /**< The joystick trackball index */
//     Uint8 padding1;
//     Uint8 padding2;
//     Uint8 padding3;
//     Sint16 xrel;        /**< The relative motion in the X direction */
//     Sint16 yrel;        /**< The relative motion in the Y direction */
// } SDL_JoyBallEvent;

// /**
//  *  \brief Joystick hat position change event structure (event.jhat.*)
//  */
// typedef struct SDL_JoyHatEvent
// {
//     Uint32 type;        /**< ::SDL_JOYHATMOTION */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
//     SDL_JoystickID which; /**< The joystick instance id */
//     Uint8 hat;          /**< The joystick hat index */
//     Uint8 value;        /**< The hat position value.
//                          *   \sa ::SDL_HAT_LEFTUP ::SDL_HAT_UP ::SDL_HAT_RIGHTUP
//                          *   \sa ::SDL_HAT_LEFT ::SDL_HAT_CENTERED ::SDL_HAT_RIGHT
//                          *   \sa ::SDL_HAT_LEFTDOWN ::SDL_HAT_DOWN ::SDL_HAT_RIGHTDOWN
//                          *
//                          *   Note that zero means the POV is centered.
//                          */
//     Uint8 padding1;
//     Uint8 padding2;
// } SDL_JoyHatEvent;

// /**
//  *  \brief Joystick button event structure (event.jbutton.*)
//  */
// typedef struct SDL_JoyButtonEvent
// {
//     Uint32 type;        /**< ::SDL_JOYBUTTONDOWN or ::SDL_JOYBUTTONUP */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
//     SDL_JoystickID which; /**< The joystick instance id */
//     Uint8 button;       /**< The joystick button index */
//     Uint8 state;        /**< ::SDL_PRESSED or ::SDL_RELEASED */
//     Uint8 padding1;
//     Uint8 padding2;
// } SDL_JoyButtonEvent;

// /**
//  *  \brief Joystick device event structure (event.jdevice.*)
//  */
// typedef struct SDL_JoyDeviceEvent
// {
//     Uint32 type;        /**< ::SDL_JOYDEVICEADDED or ::SDL_JOYDEVICEREMOVED */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
//     Sint32 which;       /**< The joystick device index for the ADDED event, instance id for the REMOVED event */
// } SDL_JoyDeviceEvent;

// /**
//  *  \brief Joysick battery level change event structure (event.jbattery.*)
//  */
// typedef struct SDL_JoyBatteryEvent
// {
//     Uint32 type;        /**< ::SDL_JOYBATTERYUPDATED */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
//     SDL_JoystickID which; /**< The joystick instance id */
//     SDL_JoystickPowerLevel level; /**< The joystick battery level */
// } SDL_JoyBatteryEvent;

// /**
//  *  \brief Game controller axis motion event structure (event.caxis.*)
//  */
// typedef struct SDL_ControllerAxisEvent
// {
//     Uint32 type;        /**< ::SDL_CONTROLLERAXISMOTION */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
//     SDL_JoystickID which; /**< The joystick instance id */
//     Uint8 axis;         /**< The controller axis (SDL_GameControllerAxis) */
//     Uint8 padding1;
//     Uint8 padding2;
//     Uint8 padding3;
//     Sint16 value;       /**< The axis value (range: -32768 to 32767) */
//     Uint16 padding4;
// } SDL_ControllerAxisEvent;

// /**
//  *  \brief Game controller button event structure (event.cbutton.*)
//  */
// typedef struct SDL_ControllerButtonEvent
// {
//     Uint32 type;        /**< ::SDL_CONTROLLERBUTTONDOWN or ::SDL_CONTROLLERBUTTONUP */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
//     SDL_JoystickID which; /**< The joystick instance id */
//     Uint8 button;       /**< The controller button (SDL_GameControllerButton) */
//     Uint8 state;        /**< ::SDL_PRESSED or ::SDL_RELEASED */
//     Uint8 padding1;
//     Uint8 padding2;
// } SDL_ControllerButtonEvent;

// /**
//  *  \brief Controller device event structure (event.cdevice.*)
//  */
// typedef struct SDL_ControllerDeviceEvent
// {
//     Uint32 type;        /**< ::SDL_CONTROLLERDEVICEADDED, ::SDL_CONTROLLERDEVICEREMOVED, or ::SDL_CONTROLLERDEVICEREMAPPED */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
//     Sint32 which;       /**< The joystick device index for the ADDED event, instance id for the REMOVED or REMAPPED event */
// } SDL_ControllerDeviceEvent;

// /**
//  *  \brief Game controller touchpad event structure (event.ctouchpad.*)
//  */
// typedef struct SDL_ControllerTouchpadEvent
// {
//     Uint32 type;        /**< ::SDL_CONTROLLERTOUCHPADDOWN or ::SDL_CONTROLLERTOUCHPADMOTION or ::SDL_CONTROLLERTOUCHPADUP */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
//     SDL_JoystickID which; /**< The joystick instance id */
//     Sint32 touchpad;    /**< The index of the touchpad */
//     Sint32 finger;      /**< The index of the finger on the touchpad */
//     float x;            /**< Normalized in the range 0...1 with 0 being on the left */
//     float y;            /**< Normalized in the range 0...1 with 0 being at the top */
//     float pressure;     /**< Normalized in the range 0...1 */
// } SDL_ControllerTouchpadEvent;

// /**
//  *  \brief Game controller sensor event structure (event.csensor.*)
//  */
// typedef struct SDL_ControllerSensorEvent
// {
//     Uint32 type;        /**< ::SDL_CONTROLLERSENSORUPDATE */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
//     SDL_JoystickID which; /**< The joystick instance id */
//     Sint32 sensor;      /**< The type of the sensor, one of the values of ::SDL_SensorType */
//     float data[3];      /**< Up to 3 values from the sensor, as defined in SDL_sensor.h */
//     Uint64 timestamp_us; /**< The timestamp of the sensor reading in microseconds, if the hardware provides this information. */
// } SDL_ControllerSensorEvent;

// /**
//  *  \brief Audio device event structure (event.adevice.*)
//  */
// typedef struct SDL_AudioDeviceEvent
// {
//     Uint32 type;        /**< ::SDL_AUDIODEVICEADDED, or ::SDL_AUDIODEVICEREMOVED */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
//     Uint32 which;       /**< The audio device index for the ADDED event (valid until next SDL_GetNumAudioDevices() call), SDL_AudioDeviceID for the REMOVED event */
//     Uint8 iscapture;    /**< zero if an output device, non-zero if a capture device. */
//     Uint8 padding1;
//     Uint8 padding2;
//     Uint8 padding3;
// } SDL_AudioDeviceEvent;

// /**
//  *  \brief Touch finger event structure (event.tfinger.*)
//  */
// typedef struct SDL_TouchFingerEvent
// {
//     Uint32 type;        /**< ::SDL_FINGERMOTION or ::SDL_FINGERDOWN or ::SDL_FINGERUP */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
//     SDL_TouchID touchId; /**< The touch device id */
//     SDL_FingerID fingerId;
//     float x;            /**< Normalized in the range 0...1 */
//     float y;            /**< Normalized in the range 0...1 */
//     float dx;           /**< Normalized in the range -1...1 */
//     float dy;           /**< Normalized in the range -1...1 */
//     float pressure;     /**< Normalized in the range 0...1 */
//     Uint32 windowID;    /**< The window underneath the finger, if any */
// } SDL_TouchFingerEvent;

// /**
//  *  \brief Multiple Finger Gesture Event (event.mgesture.*)
//  */
// typedef struct SDL_MultiGestureEvent
// {
//     Uint32 type;        /**< ::SDL_MULTIGESTURE */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
//     SDL_TouchID touchId; /**< The touch device id */
//     float dTheta;
//     float dDist;
//     float x;
//     float y;
//     Uint16 numFingers;
//     Uint16 padding;
// } SDL_MultiGestureEvent;

// /**
//  * \brief Dollar Gesture Event (event.dgesture.*)
//  */
// typedef struct SDL_DollarGestureEvent
// {
//     Uint32 type;        /**< ::SDL_DOLLARGESTURE or ::SDL_DOLLARRECORD */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
//     SDL_TouchID touchId; /**< The touch device id */
//     SDL_GestureID gestureId;
//     Uint32 numFingers;
//     float error;
//     float x;            /**< Normalized center of gesture */
//     float y;            /**< Normalized center of gesture */
// } SDL_DollarGestureEvent;

// /**
//  *  \brief An event used to request a file open by the system (event.drop.*)
//  *         This event is enabled by default, you can disable it with SDL_EventState().
//  *  \note If this event is enabled, you must free the filename in the event.
//  */
// typedef struct SDL_DropEvent
// {
//     Uint32 type;        /**< ::SDL_DROPBEGIN or ::SDL_DROPFILE or ::SDL_DROPTEXT or ::SDL_DROPCOMPLETE */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
//     char *file;         /**< The file name, which should be freed with SDL_free(), is NULL on begin/complete */
//     Uint32 windowID;    /**< The window that was dropped on, if any */
// } SDL_DropEvent;

// /**
//  *  \brief Sensor event structure (event.sensor.*)
//  */
// typedef struct SDL_SensorEvent
// {
//     Uint32 type;        /**< ::SDL_SENSORUPDATE */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
//     Sint32 which;       /**< The instance ID of the sensor */
//     float data[6];      /**< Up to 6 values from the sensor - additional values can be queried using SDL_SensorGetData() */
//     Uint64 timestamp_us; /**< The timestamp of the sensor reading in microseconds, if the hardware provides this information. */
// } SDL_SensorEvent;

// /**
//  *  \brief The "quit requested" event
//  */
// typedef struct SDL_QuitEvent
// {
//     Uint32 type;        /**< ::SDL_QUIT */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
// } SDL_QuitEvent;

// /**
//  *  \brief OS Specific event
//  */
// typedef struct SDL_OSEvent
// {
//     Uint32 type;        /**< ::SDL_QUIT */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
// } SDL_OSEvent;

// /**
//  *  \brief A user-defined event type (event.user.*)
//  */
// typedef struct SDL_UserEvent
// {
//     Uint32 type;        /**< ::SDL_USEREVENT through ::SDL_LASTEVENT-1 */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
//     Uint32 windowID;    /**< The associated window if any */
//     Sint32 code;        /**< User defined event code */
//     void *data1;        /**< User defined data pointer */
//     void *data2;        /**< User defined data pointer */
// } SDL_UserEvent;

// struct SDL_SysWMmsg;
// typedef struct SDL_SysWMmsg SDL_SysWMmsg;

// /**
//  *  \brief A video driver dependent system event (event.syswm.*)
//  *         This event is disabled by default, you can enable it with SDL_EventState()
//  *
//  *  \note If you want to use this event, you should include SDL_syswm.h.
//  */
// typedef struct SDL_SysWMEvent
// {
//     Uint32 type;        /**< ::SDL_SYSWMEVENT */
//     Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() */
//     SDL_SysWMmsg *msg;  /**< driver dependent data, defined in SDL_syswm.h */
// } SDL_SysWMEvent;

pub const SDL_Event = extern union {
    type: SDL_EventType,
    // SDL_CommonEvent common;                 /**< Common event data */
    // SDL_DisplayEvent display;               /**< Display event data */
    // SDL_WindowEvent window;                 /**< Window event data */
    key: SDL_KeyboardEvent,
    // SDL_TextEditingEvent edit;              /**< Text editing event data */
    // SDL_TextEditingExtEvent editExt;        /**< Extended text editing event data */
    // SDL_TextInputEvent text;                /**< Text input event data */
    motion: SDL_MouseMotionEvent,
    // SDL_MouseButtonEvent button;            /**< Mouse button event data */
    // SDL_MouseWheelEvent wheel;              /**< Mouse wheel event data */
    // SDL_JoyAxisEvent jaxis;                 /**< Joystick axis event data */
    // SDL_JoyBallEvent jball;                 /**< Joystick ball event data */
    // SDL_JoyHatEvent jhat;                   /**< Joystick hat event data */
    // SDL_JoyButtonEvent jbutton;             /**< Joystick button event data */
    // SDL_JoyDeviceEvent jdevice;             /**< Joystick device change event data */
    // SDL_JoyBatteryEvent jbattery;           /**< Joystick battery event data */
    // SDL_ControllerAxisEvent caxis;          /**< Game Controller axis event data */
    // SDL_ControllerButtonEvent cbutton;      /**< Game Controller button event data */
    // SDL_ControllerDeviceEvent cdevice;      /**< Game Controller device event data */
    // SDL_ControllerTouchpadEvent ctouchpad;  /**< Game Controller touchpad event data */
    // SDL_ControllerSensorEvent csensor;      /**< Game Controller sensor event data */
    // SDL_AudioDeviceEvent adevice;           /**< Audio device event data */
    // SDL_SensorEvent sensor;                 /**< Sensor event data */
    // SDL_QuitEvent quit;                     /**< Quit request event data */
    // SDL_UserEvent user;                     /**< Custom event data */
    // SDL_SysWMEvent syswm;                   /**< System dependent window event data */
    // SDL_TouchFingerEvent tfinger;           /**< Touch finger event data */
    // SDL_MultiGestureEvent mgesture;         /**< Gesture event data */
    // SDL_DollarGestureEvent dgesture;        /**< Gesture event data */
    // SDL_DropEvent drop;                     /**< Drag and drop event data */

    // See SDL_events.h for explanation
    padding: [padding_size]u8,

    const padding_size = if (@sizeOf(*anyopaque) <= 8)
        56
    else if (@sizeOf(*anyopaque) == 16)
        64
    else
        3 * @sizeOf(*anyopaque);
};

comptime {
    if (@sizeOf(SDL_Event) != SDL_Event.padding_size) {
        @compileError("@sizeOf(SDL_Event) != SDL_Event.padding_size");
    }
}

pub const SDL_Keysym = extern struct {
    scancode: SDL_Scancode,
    sym: SDL_KeyCode,
    mod: u16,
    unused: u32,
};

// SDL_Scancode
pub const SDL_Scancode = c_int;
pub const SDL_SCANCODE_UNKNOWN = 0;

pub const SDL_SCANCODE_A = 4;
pub const SDL_SCANCODE_B = 5;
pub const SDL_SCANCODE_C = 6;
pub const SDL_SCANCODE_D = 7;
pub const SDL_SCANCODE_E = 8;
pub const SDL_SCANCODE_F = 9;
pub const SDL_SCANCODE_G = 10;
pub const SDL_SCANCODE_H = 11;
pub const SDL_SCANCODE_I = 12;
pub const SDL_SCANCODE_J = 13;
pub const SDL_SCANCODE_K = 14;
pub const SDL_SCANCODE_L = 15;
pub const SDL_SCANCODE_M = 16;
pub const SDL_SCANCODE_N = 17;
pub const SDL_SCANCODE_O = 18;
pub const SDL_SCANCODE_P = 19;
pub const SDL_SCANCODE_Q = 20;
pub const SDL_SCANCODE_R = 21;
pub const SDL_SCANCODE_S = 22;
pub const SDL_SCANCODE_T = 23;
pub const SDL_SCANCODE_U = 24;
pub const SDL_SCANCODE_V = 25;
pub const SDL_SCANCODE_W = 26;
pub const SDL_SCANCODE_X = 27;
pub const SDL_SCANCODE_Y = 28;
pub const SDL_SCANCODE_Z = 29;

pub const SDL_SCANCODE_1 = 30;
pub const SDL_SCANCODE_2 = 31;
pub const SDL_SCANCODE_3 = 32;
pub const SDL_SCANCODE_4 = 33;
pub const SDL_SCANCODE_5 = 34;
pub const SDL_SCANCODE_6 = 35;
pub const SDL_SCANCODE_7 = 36;
pub const SDL_SCANCODE_8 = 37;
pub const SDL_SCANCODE_9 = 38;
pub const SDL_SCANCODE_0 = 39;

pub const SDL_SCANCODE_RETURN = 40;
pub const SDL_SCANCODE_ESCAPE = 41;
pub const SDL_SCANCODE_BACKSPACE = 42;
pub const SDL_SCANCODE_TAB = 43;
pub const SDL_SCANCODE_SPACE = 44;

pub const SDL_SCANCODE_MINUS = 45;
pub const SDL_SCANCODE_EQUALS = 46;
pub const SDL_SCANCODE_LEFTBRACKET = 47;
pub const SDL_SCANCODE_RIGHTBRACKET = 48;
pub const SDL_SCANCODE_BACKSLASH = 49;

pub const SDL_SCANCODE_NONUSHASH = 50;

pub const SDL_SCANCODE_SEMICOLON = 51;
pub const SDL_SCANCODE_APOSTROPHE = 52;
pub const SDL_SCANCODE_GRAVE = 53;

pub const SDL_SCANCODE_COMMA = 54;
pub const SDL_SCANCODE_PERIOD = 55;
pub const SDL_SCANCODE_SLASH = 56;

pub const SDL_SCANCODE_CAPSLOCK = 57;

pub const SDL_SCANCODE_F1 = 58;
pub const SDL_SCANCODE_F2 = 59;
pub const SDL_SCANCODE_F3 = 60;
pub const SDL_SCANCODE_F4 = 61;
pub const SDL_SCANCODE_F5 = 62;
pub const SDL_SCANCODE_F6 = 63;
pub const SDL_SCANCODE_F7 = 64;
pub const SDL_SCANCODE_F8 = 65;
pub const SDL_SCANCODE_F9 = 66;
pub const SDL_SCANCODE_F10 = 67;
pub const SDL_SCANCODE_F11 = 68;
pub const SDL_SCANCODE_F12 = 69;

pub const SDL_SCANCODE_PRINTSCREEN = 70;
pub const SDL_SCANCODE_SCROLLLOCK = 71;
pub const SDL_SCANCODE_PAUSE = 72;
pub const SDL_SCANCODE_INSERT = 73;
pub const SDL_SCANCODE_HOME = 74;
pub const SDL_SCANCODE_PAGEUP = 75;
pub const SDL_SCANCODE_DELETE = 76;
pub const SDL_SCANCODE_END = 77;
pub const SDL_SCANCODE_PAGEDOWN = 78;
pub const SDL_SCANCODE_RIGHT = 79;
pub const SDL_SCANCODE_LEFT = 80;
pub const SDL_SCANCODE_DOWN = 81;
pub const SDL_SCANCODE_UP = 82;

pub const SDL_SCANCODE_NUMLOCKCLEAR = 83;

pub const SDL_SCANCODE_KP_DIVIDE = 84;
pub const SDL_SCANCODE_KP_MULTIPLY = 85;
pub const SDL_SCANCODE_KP_MINUS = 86;
pub const SDL_SCANCODE_KP_PLUS = 87;
pub const SDL_SCANCODE_KP_ENTER = 88;
pub const SDL_SCANCODE_KP_1 = 89;
pub const SDL_SCANCODE_KP_2 = 90;
pub const SDL_SCANCODE_KP_3 = 91;
pub const SDL_SCANCODE_KP_4 = 92;
pub const SDL_SCANCODE_KP_5 = 93;
pub const SDL_SCANCODE_KP_6 = 94;
pub const SDL_SCANCODE_KP_7 = 95;
pub const SDL_SCANCODE_KP_8 = 96;
pub const SDL_SCANCODE_KP_9 = 97;
pub const SDL_SCANCODE_KP_0 = 98;
pub const SDL_SCANCODE_KP_PERIOD = 99;

pub const SDL_SCANCODE_NONUSBACKSLASH = 100;

pub const SDL_SCANCODE_APPLICATION = 101;
pub const SDL_SCANCODE_POWER = 102;

pub const SDL_SCANCODE_KP_EQUALS = 103;
pub const SDL_SCANCODE_F13 = 104;
pub const SDL_SCANCODE_F14 = 105;
pub const SDL_SCANCODE_F15 = 106;
pub const SDL_SCANCODE_F16 = 107;
pub const SDL_SCANCODE_F17 = 108;
pub const SDL_SCANCODE_F18 = 109;
pub const SDL_SCANCODE_F19 = 110;
pub const SDL_SCANCODE_F20 = 111;
pub const SDL_SCANCODE_F21 = 112;
pub const SDL_SCANCODE_F22 = 113;
pub const SDL_SCANCODE_F23 = 114;
pub const SDL_SCANCODE_F24 = 115;
pub const SDL_SCANCODE_EXECUTE = 116;
pub const SDL_SCANCODE_HELP = 117;
pub const SDL_SCANCODE_MENU = 118;
pub const SDL_SCANCODE_SELECT = 119;
pub const SDL_SCANCODE_STOP = 120;
pub const SDL_SCANCODE_AGAIN = 121;
pub const SDL_SCANCODE_UNDO = 122;
pub const SDL_SCANCODE_CUT = 123;
pub const SDL_SCANCODE_COPY = 124;
pub const SDL_SCANCODE_PASTE = 125;
pub const SDL_SCANCODE_FIND = 126;
pub const SDL_SCANCODE_MUTE = 127;
pub const SDL_SCANCODE_VOLUMEUP = 128;
pub const SDL_SCANCODE_VOLUMEDOWN = 129;

pub const SDL_SCANCODE_KP_COMMA = 133;
pub const SDL_SCANCODE_KP_EQUALSAS400 = 134;

pub const SDL_SCANCODE_INTERNATIONAL1 = 135;
pub const SDL_SCANCODE_INTERNATIONAL2 = 136;
pub const SDL_SCANCODE_INTERNATIONAL3 = 137;
pub const SDL_SCANCODE_INTERNATIONAL4 = 138;
pub const SDL_SCANCODE_INTERNATIONAL5 = 139;
pub const SDL_SCANCODE_INTERNATIONAL6 = 140;
pub const SDL_SCANCODE_INTERNATIONAL7 = 141;
pub const SDL_SCANCODE_INTERNATIONAL8 = 142;
pub const SDL_SCANCODE_INTERNATIONAL9 = 143;
pub const SDL_SCANCODE_LANG1 = 144;
pub const SDL_SCANCODE_LANG2 = 145;
pub const SDL_SCANCODE_LANG3 = 146;
pub const SDL_SCANCODE_LANG4 = 147;
pub const SDL_SCANCODE_LANG5 = 148;
pub const SDL_SCANCODE_LANG6 = 149;
pub const SDL_SCANCODE_LANG7 = 150;
pub const SDL_SCANCODE_LANG8 = 151;
pub const SDL_SCANCODE_LANG9 = 152;

pub const SDL_SCANCODE_ALTERASE = 153;
pub const SDL_SCANCODE_SYSREQ = 154;
pub const SDL_SCANCODE_CANCEL = 155;
pub const SDL_SCANCODE_CLEAR = 156;
pub const SDL_SCANCODE_PRIOR = 157;
pub const SDL_SCANCODE_RETURN2 = 158;
pub const SDL_SCANCODE_SEPARATOR = 159;
pub const SDL_SCANCODE_OUT = 160;
pub const SDL_SCANCODE_OPER = 161;
pub const SDL_SCANCODE_CLEARAGAIN = 162;
pub const SDL_SCANCODE_CRSEL = 163;
pub const SDL_SCANCODE_EXSEL = 164;

pub const SDL_SCANCODE_KP_00 = 176;
pub const SDL_SCANCODE_KP_000 = 177;
pub const SDL_SCANCODE_THOUSANDSSEPARATOR = 178;
pub const SDL_SCANCODE_DECIMALSEPARATOR = 179;
pub const SDL_SCANCODE_CURRENCYUNIT = 180;
pub const SDL_SCANCODE_CURRENCYSUBUNIT = 181;
pub const SDL_SCANCODE_KP_LEFTPAREN = 182;
pub const SDL_SCANCODE_KP_RIGHTPAREN = 183;
pub const SDL_SCANCODE_KP_LEFTBRACE = 184;
pub const SDL_SCANCODE_KP_RIGHTBRACE = 185;
pub const SDL_SCANCODE_KP_TAB = 186;
pub const SDL_SCANCODE_KP_BACKSPACE = 187;
pub const SDL_SCANCODE_KP_A = 188;
pub const SDL_SCANCODE_KP_B = 189;
pub const SDL_SCANCODE_KP_C = 190;
pub const SDL_SCANCODE_KP_D = 191;
pub const SDL_SCANCODE_KP_E = 192;
pub const SDL_SCANCODE_KP_F = 193;
pub const SDL_SCANCODE_KP_XOR = 194;
pub const SDL_SCANCODE_KP_POWER = 195;
pub const SDL_SCANCODE_KP_PERCENT = 196;
pub const SDL_SCANCODE_KP_LESS = 197;
pub const SDL_SCANCODE_KP_GREATER = 198;
pub const SDL_SCANCODE_KP_AMPERSAND = 199;
pub const SDL_SCANCODE_KP_DBLAMPERSAND = 200;
pub const SDL_SCANCODE_KP_VERTICALBAR = 201;
pub const SDL_SCANCODE_KP_DBLVERTICALBAR = 202;
pub const SDL_SCANCODE_KP_COLON = 203;
pub const SDL_SCANCODE_KP_HASH = 204;
pub const SDL_SCANCODE_KP_SPACE = 205;
pub const SDL_SCANCODE_KP_AT = 206;
pub const SDL_SCANCODE_KP_EXCLAM = 207;
pub const SDL_SCANCODE_KP_MEMSTORE = 208;
pub const SDL_SCANCODE_KP_MEMRECALL = 209;
pub const SDL_SCANCODE_KP_MEMCLEAR = 210;
pub const SDL_SCANCODE_KP_MEMADD = 211;
pub const SDL_SCANCODE_KP_MEMSUBTRACT = 212;
pub const SDL_SCANCODE_KP_MEMMULTIPLY = 213;
pub const SDL_SCANCODE_KP_MEMDIVIDE = 214;
pub const SDL_SCANCODE_KP_PLUSMINUS = 215;
pub const SDL_SCANCODE_KP_CLEAR = 216;
pub const SDL_SCANCODE_KP_CLEARENTRY = 217;
pub const SDL_SCANCODE_KP_BINARY = 218;
pub const SDL_SCANCODE_KP_OCTAL = 219;
pub const SDL_SCANCODE_KP_DECIMAL = 220;
pub const SDL_SCANCODE_KP_HEXADECIMAL = 221;

pub const SDL_SCANCODE_LCTRL = 224;
pub const SDL_SCANCODE_LSHIFT = 225;
pub const SDL_SCANCODE_LALT = 226;
pub const SDL_SCANCODE_LGUI = 227;
pub const SDL_SCANCODE_RCTRL = 228;
pub const SDL_SCANCODE_RSHIFT = 229;
pub const SDL_SCANCODE_RALT = 230;
pub const SDL_SCANCODE_RGUI = 231;

pub const SDL_SCANCODE_MODE = 257;

pub const SDL_SCANCODE_AUDIONEXT = 258;
pub const SDL_SCANCODE_AUDIOPREV = 259;
pub const SDL_SCANCODE_AUDIOSTOP = 260;
pub const SDL_SCANCODE_AUDIOPLAY = 261;
pub const SDL_SCANCODE_AUDIOMUTE = 262;
pub const SDL_SCANCODE_MEDIASELECT = 263;
pub const SDL_SCANCODE_WWW = 264;
pub const SDL_SCANCODE_MAIL = 265;
pub const SDL_SCANCODE_CALCULATOR = 266;
pub const SDL_SCANCODE_COMPUTER = 267;
pub const SDL_SCANCODE_AC_SEARCH = 268;
pub const SDL_SCANCODE_AC_HOME = 269;
pub const SDL_SCANCODE_AC_BACK = 270;
pub const SDL_SCANCODE_AC_FORWARD = 271;
pub const SDL_SCANCODE_AC_STOP = 272;
pub const SDL_SCANCODE_AC_REFRESH = 273;
pub const SDL_SCANCODE_AC_BOOKMARKS = 274;

pub const SDL_SCANCODE_BRIGHTNESSDOWN = 275;
pub const SDL_SCANCODE_BRIGHTNESSUP = 276;
pub const SDL_SCANCODE_DISPLAYSWITCH = 277;
pub const SDL_SCANCODE_KBDILLUMTOGGLE = 278;
pub const SDL_SCANCODE_KBDILLUMDOWN = 279;
pub const SDL_SCANCODE_KBDILLUMUP = 280;
pub const SDL_SCANCODE_EJECT = 281;
pub const SDL_SCANCODE_SLEEP = 282;

pub const SDL_SCANCODE_APP1 = 283;
pub const SDL_SCANCODE_APP2 = 284;

pub const SDL_SCANCODE_AUDIOREWIND = 285;
pub const SDL_SCANCODE_AUDIOFASTFORWARD = 286;

pub const SDL_SCANCODE_SOFTLEFT = 287;
pub const SDL_SCANCODE_SOFTRIGHT = 288;
pub const SDL_SCANCODE_CALL = 289;
pub const SDL_SCANCODE_ENDCALL = 290;

pub const SDL_NUM_SCANCODES = 512;

pub const SDLK_SCANCODE_MASK = (1 << 30);
pub fn SDL_SCANCODE_TO_KEYCODE(comptime x: comptime_int) comptime_int {
    return (x | SDLK_SCANCODE_MASK);
}

// SDL_KeyCode
pub const SDL_KeyCode = c_int;
pub const SDLK_UNKNOWN = 0;

pub const SDLK_RETURN = '\r';
pub const SDLK_ESCAPE = '\x1B';
pub const SDLK_BACKSPACE = '\x08'; // \b in original source
pub const SDLK_TAB = '\t';
pub const SDLK_SPACE = ' ';
pub const SDLK_EXCLAIM = '!';
pub const SDLK_QUOTEDBL = '"';
pub const SDLK_HASH = '#';
pub const SDLK_PERCENT = '%';
pub const SDLK_DOLLAR = '$';
pub const SDLK_AMPERSAND = '&';
pub const SDLK_QUOTE = '\'';
pub const SDLK_LEFTPAREN = '(';
pub const SDLK_RIGHTPAREN = ')';
pub const SDLK_ASTERISK = '*';
pub const SDLK_PLUS = '+';
pub const SDLK_COMMA = ',';
pub const SDLK_MINUS = '-';
pub const SDLK_PERIOD = '.';
pub const SDLK_SLASH = '/';
pub const SDLK_0 = '0';
pub const SDLK_1 = '1';
pub const SDLK_2 = '2';
pub const SDLK_3 = '3';
pub const SDLK_4 = '4';
pub const SDLK_5 = '5';
pub const SDLK_6 = '6';
pub const SDLK_7 = '7';
pub const SDLK_8 = '8';
pub const SDLK_9 = '9';
pub const SDLK_COLON = ':';
pub const SDLK_SEMICOLON = ';';
pub const SDLK_LESS = '<';
pub const SDLK_EQUALS = '=';
pub const SDLK_GREATER = '>';
pub const SDLK_QUESTION = '?';
pub const SDLK_AT = '@';

pub const SDLK_LEFTBRACKET = '[';
pub const SDLK_BACKSLASH = '\\';
pub const SDLK_RIGHTBRACKET = ']';
pub const SDLK_CARET = '^';
pub const SDLK_UNDERSCORE = '_';
pub const SDLK_BACKQUOTE = '`';
pub const SDLK_a = 'a';
pub const SDLK_b = 'b';
pub const SDLK_c = 'c';
pub const SDLK_d = 'd';
pub const SDLK_e = 'e';
pub const SDLK_f = 'f';
pub const SDLK_g = 'g';
pub const SDLK_h = 'h';
pub const SDLK_i = 'i';
pub const SDLK_j = 'j';
pub const SDLK_k = 'k';
pub const SDLK_l = 'l';
pub const SDLK_m = 'm';
pub const SDLK_n = 'n';
pub const SDLK_o = 'o';
pub const SDLK_p = 'p';
pub const SDLK_q = 'q';
pub const SDLK_r = 'r';
pub const SDLK_s = 's';
pub const SDLK_t = 't';
pub const SDLK_u = 'u';
pub const SDLK_v = 'v';
pub const SDLK_w = 'w';
pub const SDLK_x = 'x';
pub const SDLK_y = 'y';
pub const SDLK_z = 'z';

pub const SDLK_CAPSLOCK = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_CAPSLOCK);

pub const SDLK_F1 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F1);
pub const SDLK_F2 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F2);
pub const SDLK_F3 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F3);
pub const SDLK_F4 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F4);
pub const SDLK_F5 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F5);
pub const SDLK_F6 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F6);
pub const SDLK_F7 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F7);
pub const SDLK_F8 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F8);
pub const SDLK_F9 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F9);
pub const SDLK_F10 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F10);
pub const SDLK_F11 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F11);
pub const SDLK_F12 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F12);

pub const SDLK_PRINTSCREEN = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_PRINTSCREEN);
pub const SDLK_SCROLLLOCK = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_SCROLLLOCK);
pub const SDLK_PAUSE = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_PAUSE);
pub const SDLK_INSERT = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_INSERT);
pub const SDLK_HOME = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_HOME);
pub const SDLK_PAGEUP = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_PAGEUP);
pub const SDLK_DELETE = '\x7F';
pub const SDLK_END = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_END);
pub const SDLK_PAGEDOWN = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_PAGEDOWN);
pub const SDLK_RIGHT = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_RIGHT);
pub const SDLK_LEFT = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_LEFT);
pub const SDLK_DOWN = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_DOWN);
pub const SDLK_UP = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_UP);

pub const SDLK_NUMLOCKCLEAR = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_NUMLOCKCLEAR);
pub const SDLK_KP_DIVIDE = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_DIVIDE);
pub const SDLK_KP_MULTIPLY = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_MULTIPLY);
pub const SDLK_KP_MINUS = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_MINUS);
pub const SDLK_KP_PLUS = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_PLUS);
pub const SDLK_KP_ENTER = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_ENTER);
pub const SDLK_KP_1 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_1);
pub const SDLK_KP_2 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_2);
pub const SDLK_KP_3 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_3);
pub const SDLK_KP_4 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_4);
pub const SDLK_KP_5 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_5);
pub const SDLK_KP_6 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_6);
pub const SDLK_KP_7 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_7);
pub const SDLK_KP_8 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_8);
pub const SDLK_KP_9 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_9);
pub const SDLK_KP_0 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_0);
pub const SDLK_KP_PERIOD = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_PERIOD);

pub const SDLK_APPLICATION = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_APPLICATION);
pub const SDLK_POWER = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_POWER);
pub const SDLK_KP_EQUALS = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_EQUALS);
pub const SDLK_F13 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F13);
pub const SDLK_F14 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F14);
pub const SDLK_F15 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F15);
pub const SDLK_F16 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F16);
pub const SDLK_F17 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F17);
pub const SDLK_F18 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F18);
pub const SDLK_F19 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F19);
pub const SDLK_F20 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F20);
pub const SDLK_F21 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F21);
pub const SDLK_F22 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F22);
pub const SDLK_F23 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F23);
pub const SDLK_F24 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F24);
pub const SDLK_EXECUTE = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_EXECUTE);
pub const SDLK_HELP = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_HELP);
pub const SDLK_MENU = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_MENU);
pub const SDLK_SELECT = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_SELECT);
pub const SDLK_STOP = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_STOP);
pub const SDLK_AGAIN = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_AGAIN);
pub const SDLK_UNDO = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_UNDO);
pub const SDLK_CUT = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_CUT);
pub const SDLK_COPY = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_COPY);
pub const SDLK_PASTE = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_PASTE);
pub const SDLK_FIND = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_FIND);
pub const SDLK_MUTE = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_MUTE);
pub const SDLK_VOLUMEUP = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_VOLUMEUP);
pub const SDLK_VOLUMEDOWN = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_VOLUMEDOWN);
pub const SDLK_KP_COMMA = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_COMMA);
pub const SDLK_KP_EQUALSAS400 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_EQUALSAS400);

pub const SDLK_ALTERASE = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_ALTERASE);
pub const SDLK_SYSREQ = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_SYSREQ);
pub const SDLK_CANCEL = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_CANCEL);
pub const SDLK_CLEAR = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_CLEAR);
pub const SDLK_PRIOR = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_PRIOR);
pub const SDLK_RETURN2 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_RETURN2);
pub const SDLK_SEPARATOR = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_SEPARATOR);
pub const SDLK_OUT = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_OUT);
pub const SDLK_OPER = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_OPER);
pub const SDLK_CLEARAGAIN = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_CLEARAGAIN);
pub const SDLK_CRSEL = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_CRSEL);
pub const SDLK_EXSEL = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_EXSEL);

pub const SDLK_KP_00 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_00);
pub const SDLK_KP_000 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_000);
pub const SDLK_THOUSANDSSEPARATOR = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_THOUSANDSSEPARATOR);
pub const SDLK_DECIMALSEPARATOR = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_DECIMALSEPARATOR);
pub const SDLK_CURRENCYUNIT = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_CURRENCYUNIT);
pub const SDLK_CURRENCYSUBUNIT = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_CURRENCYSUBUNIT);
pub const SDLK_KP_LEFTPAREN = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_LEFTPAREN);
pub const SDLK_KP_RIGHTPAREN = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_RIGHTPAREN);
pub const SDLK_KP_LEFTBRACE = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_LEFTBRACE);
pub const SDLK_KP_RIGHTBRACE = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_RIGHTBRACE);
pub const SDLK_KP_TAB = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_TAB);
pub const SDLK_KP_BACKSPACE = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_BACKSPACE);
pub const SDLK_KP_A = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_A);
pub const SDLK_KP_B = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_B);
pub const SDLK_KP_C = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_C);
pub const SDLK_KP_D = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_D);
pub const SDLK_KP_E = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_E);
pub const SDLK_KP_F = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_F);
pub const SDLK_KP_XOR = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_XOR);
pub const SDLK_KP_POWER = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_POWER);
pub const SDLK_KP_PERCENT = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_PERCENT);
pub const SDLK_KP_LESS = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_LESS);
pub const SDLK_KP_GREATER = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_GREATER);
pub const SDLK_KP_AMPERSAND = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_AMPERSAND);
pub const SDLK_KP_DBLAMPERSAND = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_DBLAMPERSAND);
pub const SDLK_KP_VERTICALBAR = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_VERTICALBAR);
pub const SDLK_KP_DBLVERTICALBAR = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_DBLVERTICALBAR);
pub const SDLK_KP_COLON = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_COLON);
pub const SDLK_KP_HASH = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_HASH);
pub const SDLK_KP_SPACE = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_SPACE);
pub const SDLK_KP_AT = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_AT);
pub const SDLK_KP_EXCLAM = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_EXCLAM);
pub const SDLK_KP_MEMSTORE = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_MEMSTORE);
pub const SDLK_KP_MEMRECALL = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_MEMRECALL);
pub const SDLK_KP_MEMCLEAR = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_MEMCLEAR);
pub const SDLK_KP_MEMADD = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_MEMADD);
pub const SDLK_KP_MEMSUBTRACT = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_MEMSUBTRACT);
pub const SDLK_KP_MEMMULTIPLY = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_MEMMULTIPLY);
pub const SDLK_KP_MEMDIVIDE = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_MEMDIVIDE);
pub const SDLK_KP_PLUSMINUS = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_PLUSMINUS);
pub const SDLK_KP_CLEAR = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_CLEAR);
pub const SDLK_KP_CLEARENTRY = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_CLEARENTRY);
pub const SDLK_KP_BINARY = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_BINARY);
pub const SDLK_KP_OCTAL = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_OCTAL);
pub const SDLK_KP_DECIMAL = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_DECIMAL);
pub const SDLK_KP_HEXADECIMAL = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KP_HEXADECIMAL);

pub const SDLK_LCTRL = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_LCTRL);
pub const SDLK_LSHIFT = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_LSHIFT);
pub const SDLK_LALT = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_LALT);
pub const SDLK_LGUI = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_LGUI);
pub const SDLK_RCTRL = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_RCTRL);
pub const SDLK_RSHIFT = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_RSHIFT);
pub const SDLK_RALT = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_RALT);
pub const SDLK_RGUI = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_RGUI);

pub const SDLK_MODE = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_MODE);

pub const SDLK_AUDIONEXT = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_AUDIONEXT);
pub const SDLK_AUDIOPREV = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_AUDIOPREV);
pub const SDLK_AUDIOSTOP = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_AUDIOSTOP);
pub const SDLK_AUDIOPLAY = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_AUDIOPLAY);
pub const SDLK_AUDIOMUTE = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_AUDIOMUTE);
pub const SDLK_MEDIASELECT = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_MEDIASELECT);
pub const SDLK_WWW = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_WWW);
pub const SDLK_MAIL = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_MAIL);
pub const SDLK_CALCULATOR = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_CALCULATOR);
pub const SDLK_COMPUTER = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_COMPUTER);
pub const SDLK_AC_SEARCH = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_AC_SEARCH);
pub const SDLK_AC_HOME = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_AC_HOME);
pub const SDLK_AC_BACK = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_AC_BACK);
pub const SDLK_AC_FORWARD = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_AC_FORWARD);
pub const SDLK_AC_STOP = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_AC_STOP);
pub const SDLK_AC_REFRESH = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_AC_REFRESH);
pub const SDLK_AC_BOOKMARKS = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_AC_BOOKMARKS);

pub const SDLK_BRIGHTNESSDOWN = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_BRIGHTNESSDOWN);
pub const SDLK_BRIGHTNESSUP = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_BRIGHTNESSUP);
pub const SDLK_DISPLAYSWITCH = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_DISPLAYSWITCH);
pub const SDLK_KBDILLUMTOGGLE = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KBDILLUMTOGGLE);
pub const SDLK_KBDILLUMDOWN = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KBDILLUMDOWN);
pub const SDLK_KBDILLUMUP = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_KBDILLUMUP);
pub const SDLK_EJECT = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_EJECT);
pub const SDLK_SLEEP = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_SLEEP);
pub const SDLK_APP1 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_APP1);
pub const SDLK_APP2 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_APP2);

pub const SDLK_AUDIOREWIND = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_AUDIOREWIND);
pub const SDLK_AUDIOFASTFORWARD = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_AUDIOFASTFORWARD);

pub const SDLK_SOFTLEFT = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_SOFTLEFT);
pub const SDLK_SOFTRIGHT = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_SOFTRIGHT);
pub const SDLK_CALL = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_CALL);
pub const SDLK_ENDCALL = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_ENDCALL);

// SDL_Keymod

pub const KMOD_NONE = 0x0000;
pub const KMOD_LSHIFT = 0x0001;
pub const KMOD_RSHIFT = 0x0002;
pub const KMOD_LCTRL = 0x0040;
pub const KMOD_RCTRL = 0x0080;
pub const KMOD_LALT = 0x0100;
pub const KMOD_RALT = 0x0200;
pub const KMOD_LGUI = 0x0400;
pub const KMOD_RGUI = 0x0800;
pub const KMOD_NUM = 0x1000;
pub const KMOD_CAPS = 0x2000;
pub const KMOD_MODE = 0x4000;
pub const KMOD_SCROLL = 0x8000;

pub const KMOD_CTRL = KMOD_LCTRL | KMOD_RCTRL;
pub const KMOD_SHIFT = KMOD_LSHIFT | KMOD_RSHIFT;
pub const KMOD_ALT = KMOD_LALT | KMOD_RALT;
pub const KMOD_GUI = KMOD_LGUI | KMOD_RGUI;

pub const KMOD_RESERVED = KMOD_SCROLL;

pub const SDL_Keycode = i32;

pub extern fn SDL_PollEvent(event: *SDL_Event) c_int;

// GL
pub const SDL_GLContext = *opaque {};
pub extern fn SDL_GL_CreateContext(window: *SDL_Window) ?SDL_GLContext;
pub extern fn SDL_GL_DeleteContext(?SDL_GLContext) void;
pub extern fn SDL_GL_SwapWindow(*SDL_Window) void;

pub extern fn SDL_GL_GetProcAddress(proc: [*:0]const u8) ?*anyopaque;
pub extern fn SDL_GL_SetAttribute(attr: SDL_GLattr, value: c_int) c_int;

// relies on count-up behavior
const SDL_GLattr = enum(c_int) {
    SDL_GL_RED_SIZE,
    SDL_GL_GREEN_SIZE,
    SDL_GL_BLUE_SIZE,
    SDL_GL_ALPHA_SIZE,
    SDL_GL_BUFFER_SIZE,
    SDL_GL_DOUBLEBUFFER,
    SDL_GL_DEPTH_SIZE,
    SDL_GL_STENCIL_SIZE,
    SDL_GL_ACCUM_RED_SIZE,
    SDL_GL_ACCUM_GREEN_SIZE,
    SDL_GL_ACCUM_BLUE_SIZE,
    SDL_GL_ACCUM_ALPHA_SIZE,
    SDL_GL_STEREO,
    SDL_GL_MULTISAMPLEBUFFERS,
    SDL_GL_MULTISAMPLESAMPLES,
    SDL_GL_ACCELERATED_VISUAL,
    SDL_GL_RETAINED_BACKING,
    SDL_GL_CONTEXT_MAJOR_VERSION,
    SDL_GL_CONTEXT_MINOR_VERSION,
    SDL_GL_CONTEXT_EGL,
    SDL_GL_CONTEXT_FLAGS,
    SDL_GL_CONTEXT_PROFILE_MASK,
    SDL_GL_SHARE_WITH_CURRENT_CONTEXT,
    SDL_GL_FRAMEBUFFER_SRGB_CAPABLE,
    SDL_GL_CONTEXT_RELEASE_BEHAVIOR,
    SDL_GL_CONTEXT_RESET_NOTIFICATION,
    SDL_GL_CONTEXT_NO_ERROR,
    SDL_GL_FLOATBUFFERS,
};

pub const SDL_GLprofile = c_int;
pub const SDL_GL_CONTEXT_PROFILE_CORE = 0x0001;
pub const SDL_GL_CONTEXT_PROFILE_COMPATIBILITY = 0x0002;
pub const SDL_GL_CONTEXT_PROFILE_ES = 0x0004;

pub extern fn SDL_GetTicks64() u64;

// Audio bits
pub const SDL_AudioDeviceID = u32;
pub const SDL_AudioFormat = u16;
pub const SDL_AudioSpec = extern struct {
    freq: c_int,
    format: SDL_AudioFormat,
    channels: u8,
    silence: u8,
    samples: u16,
    padding: u16,
    size: u32,
    callback: SDL_AudioCallback,
    userdata: ?*anyopaque,
};
pub const SDL_AudioCallback = *const fn (userdata: ?*anyopaque, stream: [*]u8, len: c_int) callconv(.C) void;
pub const AUDIO_U8 = 0x0008;
pub const AUDIO_S8 = 0x8008;
pub const AUDIO_U16LSB = 0x0010;
pub const AUDIO_S16LSB = 0x8010;
pub const AUDIO_U16MSB = 0x1010;
pub const AUDIO_S16MSB = 0x9010;
pub const AUDIO_U16 = AUDIO_U16LSB;
pub const AUDIO_S16 = AUDIO_S16LSB;

pub extern fn SDL_OpenAudioDevice(
    device: ?[*:0]const u8,
    iscapture: c_int,
    desired: *const SDL_AudioSpec,
    obtained: *SDL_AudioSpec,
    allowed_changes: c_int,
) SDL_AudioDeviceID;
pub extern fn SDL_CloseAudioDevice(dev: SDL_AudioDeviceID) void;
pub extern fn SDL_PauseAudioDevice(dev: SDL_AudioDeviceID, pause_on: c_int) void;
pub extern fn SDL_LockAudioDevice(dev: SDL_AudioDeviceID) void;
pub extern fn SDL_UnlockAudioDevice(dev: SDL_AudioDeviceID) void;

pub extern fn SDL_GetKeyboardState(numkeys: ?*c_int) [*]const u8;
