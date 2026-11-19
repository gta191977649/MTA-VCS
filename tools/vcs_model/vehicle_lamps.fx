texture LampAtlas;

technique vcs_lamp_atlas {
    pass Lamp {
        Texture[0] = (LampAtlas);
    }
}
