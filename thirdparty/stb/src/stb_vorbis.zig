pub extern fn stb_vorbis_decode_filename(
    filename: [*:0]const u8,
    channels: *c_int,
    sample_rate: *c_int,
    output: *[*]c_short,
) c_int;
