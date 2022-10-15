const stbi_uc = u8;

pub extern fn stbi_load(
    filename: [*:0]const u8,
    x: *c_int,
    y: *c_int,
    channels_in_file: *c_int,
    desired_channels: c_int,
) [*]stbi_uc;

pub extern fn stbi_image_free(
    retval_from_stbi_load: *anyopaque,
) void;

pub extern fn stbi_set_flip_vertically_on_load(
    flag_true_if_should_flip: c_int,
) void;
