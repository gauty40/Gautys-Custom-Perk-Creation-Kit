autoexec mp_bo6_store_init()
{
    level thread mp_bo6_store_sync();
    level thread mp_cp_augment_persistence_main();
}

mp_bo6_store_sync()
{
    nengine_store_load("bo6", "picks");
    level.mp_bo6_stored = nengine_store_get("bo6", "picks");
    if (!isdefined(level.mp_bo6_stored))
    {
        level.mp_bo6_stored = "";
    }
    if (level.mp_bo6_stored != "")
    {
        setdvar("kronos_bo6_var", mp_bo6_store_merge(getdvar("kronos_bo6_var", ""), level.mp_bo6_stored, mp_bo6_store_cap()));
    }
    level.mp_bo6_saved = "";
    for (;;)
    {
        wait 0.5;
        if (getdvar("kronos_bo6_var", "") != level.mp_bo6_saved)
        {
            level.mp_bo6_saved = getdvar("kronos_bo6_var", "");
            level.mp_bo6_stored = mp_bo6_store_merge(level.mp_bo6_saved, level.mp_bo6_stored, 1000);
            nengine_store_set("bo6", "picks", level.mp_bo6_stored);
            nengine_store_save("bo6", "picks");
        }
    }
}

mp_cp_augment_persistence_main()
{
    level.mp_cp_aug_store = "bo7_custom_perks";
    level.mp_cp_aug_save = "augment_selections";
    level.mp_cp_aug_keys = [];
    level.mp_cp_aug_dvars = [];

    level.mp_cp_aug_keys[0] = "bandolier";
    level.mp_cp_aug_dvars[0] = @"bo7_cp_bandolier_pick";
    level.mp_cp_aug_keys[1] = "tortoise";
    level.mp_cp_aug_dvars[1] = @"bo7_cp_tortoise_pick";
    level.mp_cp_aug_keys[2] = "gautys_gold";
    level.mp_cp_aug_dvars[2] = @"bo7_cp_gautys_gold_pick";
    level.mp_cp_aug_keys[3] = "electric_cherry";
    level.mp_cp_aug_dvars[3] = @"bo7_cp_electric_cherry_pick";
    level.mp_cp_aug_keys[4] = "off_bandolier";
    level.mp_cp_aug_dvars[4] = @"bo7_cp_off_bandolier";
    level.mp_cp_aug_keys[5] = "off_tortoise";
    level.mp_cp_aug_dvars[5] = @"bo7_cp_off_tortoise";
    level.mp_cp_aug_keys[6] = "off_gautys_gold";
    level.mp_cp_aug_dvars[6] = @"bo7_cp_off_gautys_gold";
    level.mp_cp_aug_keys[7] = "off_electric_cherry";
    level.mp_cp_aug_dvars[7] = @"bo7_cp_off_electric_cherry";
    level.mp_cp_aug_keys[8] = "off_jug2";
    level.mp_cp_aug_dvars[8] = @"bo7_cp_off_jug2";
    level.mp_cp_aug_keys[9] = "off_native_juggernog";
    level.mp_cp_aug_dvars[9] = @"bo7_cp_off_native_juggernog";
    level.mp_cp_aug_keys[10] = "off_native_quick_revive";
    level.mp_cp_aug_dvars[10] = @"bo7_cp_off_native_quick_revive";
    level.mp_cp_aug_keys[11] = "off_native_speedcola";
    level.mp_cp_aug_dvars[11] = @"bo7_cp_off_native_speedcola";
    level.mp_cp_aug_keys[12] = "off_native_staminup";
    level.mp_cp_aug_dvars[12] = @"bo7_cp_off_native_staminup";
    level.mp_cp_aug_keys[13] = "off_native_deadshot";
    level.mp_cp_aug_dvars[13] = @"bo7_cp_off_native_deadshot";
    level.mp_cp_aug_keys[14] = "off_native_elemental_pop";
    level.mp_cp_aug_dvars[14] = @"bo7_cp_off_native_elemental_pop";
    level.mp_cp_aug_keys[15] = "off_native_phd_flopper";
    level.mp_cp_aug_dvars[15] = @"bo7_cp_off_native_phd_flopper";
    level.mp_cp_aug_keys[16] = "off_native_death_perception";
    level.mp_cp_aug_dvars[16] = @"bo7_cp_off_native_death_perception";
    level.mp_cp_aug_keys[17] = "off_native_vulture_aid";
    level.mp_cp_aug_dvars[17] = @"bo7_cp_off_native_vulture_aid";
    level.mp_cp_aug_keys[18] = "off_native_m_mod";
    level.mp_cp_aug_dvars[18] = @"bo7_cp_off_native_m_mod";
    level.mp_cp_aug_keys[19] = "off_native_d_mod";
    level.mp_cp_aug_dvars[19] = @"bo7_cp_off_native_d_mod";
    level.mp_cp_aug_keys[20] = "off_native_w_mod";
    level.mp_cp_aug_dvars[20] = @"bo7_cp_off_native_w_mod";
    level.mp_cp_aug_keys[21] = "off_native_y_mod";
    level.mp_cp_aug_dvars[21] = @"bo7_cp_off_native_y_mod";
    level.mp_cp_aug_keys[22] = "off_native_z_mod";
    level.mp_cp_aug_dvars[22] = @"bo7_cp_off_native_z_mod";
    level.mp_cp_aug_keys[23] = "eternal_frame_style";
    level.mp_cp_aug_dvars[23] = @"bo7_cp_eternal_frame_style";
    level.mp_cp_aug_keys[24] = "jug2";
    level.mp_cp_aug_dvars[24] = @"bo7_cp_jug2_pick";

    // perk on/off switches: 1 = switched off by the player (0 or unset = on). Saved like the augment picks.



    level.mp_cp_aug_store_loaded = nengine_store_load( level.mp_cp_aug_store, level.mp_cp_aug_save );
    level.mp_cp_aug_last_values = [];
    level.mp_cp_aug_changed = false;

    for ( i = 0; i < level.mp_cp_aug_keys.size; i++ )
    {
        s_current = getdvar( level.mp_cp_aug_dvars[i], "" );
        v_stored = nengine_store_get( level.mp_cp_aug_store, level.mp_cp_aug_keys[i] );

        if ( level.mp_cp_aug_keys[i] == "electric_cherry" && !isdefined( v_stored ) )
        {
            v_stored = nengine_store_get( level.mp_cp_aug_store, "cherry" );
            if ( !isdefined( v_stored ) )
            {
                s_legacy = getdvar( @"bo7_cp_cherry_pick", "" );
                if ( s_legacy != "" )
                {
                    v_stored = s_legacy;
                }
            }

            if ( isdefined( v_stored ) )
            {
                nengine_store_set( level.mp_cp_aug_store, "electric_cherry", v_stored );
                level.mp_cp_aug_changed = true;
                logstring( "Custom perk augment selection migrated from cherry to electric_cherry" );
            }
        }

        if ( level.mp_cp_aug_store_loaded && isdefined( v_stored ) )
        {
            n_stored = int( v_stored );
            if ( n_stored >= 0 && n_stored <= 999 )
            {
                s_current = "" + n_stored;
                setdvar( level.mp_cp_aug_dvars[i], s_current );
                logstring( "Custom perk augment restored " + level.mp_cp_aug_keys[i] + "=" + s_current );
            }
            else
            {
                logstring( "Custom perk augment store contains an invalid selection for " + level.mp_cp_aug_keys[i] );
            }
        }

        if ( s_current != "" )
        {
            n_current = int( s_current );
            if ( n_current >= 0 && n_current <= 999 )
            {
                if ( !level.mp_cp_aug_store_loaded || !isdefined( v_stored ) )
                {
                    nengine_store_set( level.mp_cp_aug_store, level.mp_cp_aug_keys[i], n_current );
                    level.mp_cp_aug_changed = true;
                }
            }
            else
            {
                logstring( "Custom perk augment dvar contains an invalid selection for " + level.mp_cp_aug_keys[i] );
                s_current = "";
            }
        }

        level.mp_cp_aug_last_values[i] = s_current;
    }

    if ( level.mp_cp_aug_changed )
    {
        nengine_store_save( level.mp_cp_aug_store, level.mp_cp_aug_save );
    }
    if ( level.mp_cp_aug_store_loaded )
    {
        setdvar( @"bo7_cp_augment_store_status", "loaded" );
        logstring( "Custom perk augment selections loaded" );
    }
    else if ( level.mp_cp_aug_changed )
    {
        setdvar( @"bo7_cp_augment_store_status", "saved" );
        logstring( "Custom perk augment selections initialized from current dvars" );
    }
    else
    {
        setdvar( @"bo7_cp_augment_store_status", "watching" );
        logstring( "Custom perk augment store watching for selections" );
    }

    for ( ;; )
    {
        wait 0.1;
        level.mp_cp_aug_changed = false;

        for ( i = 0; i < level.mp_cp_aug_keys.size; i++ )
        {
            s_current = getdvar( level.mp_cp_aug_dvars[i], "" );
            if ( s_current == "" || s_current == level.mp_cp_aug_last_values[i] )
            {
                continue;
            }

            n_current = int( s_current );
            if ( n_current < 0 || n_current > 999 )
            {
                level.mp_cp_aug_last_values[i] = s_current;
                logstring( "Custom perk augment selection ignored for " + level.mp_cp_aug_keys[i] + ": value out of range" );
                continue;
            }

            nengine_store_set( level.mp_cp_aug_store, level.mp_cp_aug_keys[i], n_current );
            level.mp_cp_aug_last_values[i] = s_current;
            level.mp_cp_aug_changed = true;
        }

        if ( level.mp_cp_aug_changed )
        {
            nengine_store_save( level.mp_cp_aug_store, level.mp_cp_aug_save );
            setdvar( @"bo7_cp_augment_store_status", "saved" );
            logstring( "Custom perk augment selections saved" );
        }
    }
}

mp_bo6_store_cap()
{
    level.mp_bo6_cparts = strtok(getdvar("kronos_bo6_var", "") + ";" + level.mp_bo6_stored, ";");
    level.mp_bo6_ci = 0;
    while (level.mp_bo6_ci < level.mp_bo6_cparts.size)
    {
        level.mp_bo6_ckv = strtok(level.mp_bo6_cparts[level.mp_bo6_ci], "=");
        if (level.mp_bo6_ckv.size == 2 && level.mp_bo6_ckv[0] == "cap" && int(level.mp_bo6_ckv[1]) >= 900)
        {
            if (int(level.mp_bo6_ckv[1]) > 1000)
            {
                return 1000;
            }
            return int(level.mp_bo6_ckv[1]);
        }
        level.mp_bo6_ci = level.mp_bo6_ci + 1;
    }
    return 900;
}

mp_bo6_store_base(key)
{
    level.mp_bo6_bparts = strtok(key, "@");
    if (level.mp_bo6_bparts.size >= 1)
    {
        return level.mp_bo6_bparts[0];
    }
    return key;
}

mp_bo6_store_merge(cur, stored, cap)
{
    level.mp_bo6_have = [];
    level.mp_bo6_parts = strtok(cur, ";");
    level.mp_bo6_mi = 0;
    while (level.mp_bo6_mi < level.mp_bo6_parts.size)
    {
        level.mp_bo6_mkv = strtok(level.mp_bo6_parts[level.mp_bo6_mi], "=");
        if (level.mp_bo6_mkv.size >= 1)
        {
            level.mp_bo6_have[mp_bo6_store_base(level.mp_bo6_mkv[0])] = 1;
        }
        level.mp_bo6_mi = level.mp_bo6_mi + 1;
    }
    level.mp_bo6_parts = strtok(stored, ";");
    level.mp_bo6_take = [];
    level.mp_bo6_len = cur.size;
    level.mp_bo6_mi = 0;
    while (level.mp_bo6_mi < level.mp_bo6_parts.size)
    {
        level.mp_bo6_mkv = strtok(level.mp_bo6_parts[level.mp_bo6_mi], "=");
        if (level.mp_bo6_mkv.size >= 1 && level.mp_bo6_mkv[0] == "melee" && !isdefined(level.mp_bo6_have["melee"]))
        {
            level.mp_bo6_take[level.mp_bo6_mi] = 1;
            level.mp_bo6_len = level.mp_bo6_len + level.mp_bo6_parts[level.mp_bo6_mi].size + 1;
        }
        level.mp_bo6_mi = level.mp_bo6_mi + 1;
    }
    level.mp_bo6_mi = level.mp_bo6_parts.size - 1;
    while (level.mp_bo6_mi >= 0)
    {
        level.mp_bo6_mkv = strtok(level.mp_bo6_parts[level.mp_bo6_mi], "=");
        if (level.mp_bo6_mkv.size == 2 && !isdefined(level.mp_bo6_have[mp_bo6_store_base(level.mp_bo6_mkv[0])]) && !isdefined(level.mp_bo6_take[level.mp_bo6_mi]) && level.mp_bo6_len + level.mp_bo6_parts[level.mp_bo6_mi].size + 1 < cap)
        {
            level.mp_bo6_take[level.mp_bo6_mi] = 1;
            level.mp_bo6_len = level.mp_bo6_len + level.mp_bo6_parts[level.mp_bo6_mi].size + 1;
        }
        level.mp_bo6_mi = level.mp_bo6_mi - 1;
    }
    level.mp_bo6_merged = "";
    level.mp_bo6_mi = 0;
    while (level.mp_bo6_mi < level.mp_bo6_parts.size)
    {
        if (isdefined(level.mp_bo6_take[level.mp_bo6_mi]))
        {
            level.mp_bo6_merged = level.mp_bo6_merged + level.mp_bo6_parts[level.mp_bo6_mi] + ";";
        }
        level.mp_bo6_mi = level.mp_bo6_mi + 1;
    }
    return level.mp_bo6_merged + cur;
}

autoexec mp_bo6_zmb_init()
{
    level thread mp_bo6_zmb_sync();
}

mp_bo6_zmb_name(chunk)
{
    if (chunk == 0)
    {
        return "kronos_bo6_zmb";
    }
    return "kronos_bo6_zmb" + chunk;
}

mp_bo6_zmb_key(chunk)
{
    if (chunk == 0)
    {
        return "builds";
    }
    return "builds" + chunk;
}

mp_bo6_zmb_sync()
{
    level.mp_bo6_zmb_n = 40;
    level.mp_bo6_zmb_loaded = 0;
    level.mp_bo6_zmb_ok = 0;
    level.mp_bo6_zmb_saved = [];
    level.mp_bo6_zmb_c = 0;
    while (level.mp_bo6_zmb_c < level.mp_bo6_zmb_n)
    {
        if (getdvar(mp_bo6_zmb_name(level.mp_bo6_zmb_c), "") == "")
        {
            if (!level.mp_bo6_zmb_loaded)
            {
                level.mp_bo6_zmb_loaded = 1;
                level.mp_bo6_zmb_ok = nengine_store_load("bo6zmb", "builds");
            }
            level.mp_bo6_zmb_file = "";
            if (level.mp_bo6_zmb_ok)
            {
                level.mp_bo6_zmb_file = nengine_store_get("bo6zmb", mp_bo6_zmb_key(level.mp_bo6_zmb_c));
            }
            if (!isdefined(level.mp_bo6_zmb_file) || !function_f20826a3e52aa5cf(level.mp_bo6_zmb_file))
            {
                level.mp_bo6_zmb_file = "";
            }
            setdvar(mp_bo6_zmb_name(level.mp_bo6_zmb_c), level.mp_bo6_zmb_file);
        }
        level.mp_bo6_zmb_saved[level.mp_bo6_zmb_c] = getdvar(mp_bo6_zmb_name(level.mp_bo6_zmb_c), "");
        level.mp_bo6_zmb_c = level.mp_bo6_zmb_c + 1;
    }
    for (;;)
    {
        wait 0.5;
        level.mp_bo6_zmb_dirty = 0;
        level.mp_bo6_zmb_c = 0;
        while (level.mp_bo6_zmb_c < level.mp_bo6_zmb_n)
        {
            if (getdvar(mp_bo6_zmb_name(level.mp_bo6_zmb_c), "") != level.mp_bo6_zmb_saved[level.mp_bo6_zmb_c])
            {
                level.mp_bo6_zmb_saved[level.mp_bo6_zmb_c] = getdvar(mp_bo6_zmb_name(level.mp_bo6_zmb_c), "");
                level.mp_bo6_zmb_dirty = 1;
            }
            level.mp_bo6_zmb_c = level.mp_bo6_zmb_c + 1;
        }
        if (level.mp_bo6_zmb_dirty)
        {
            level.mp_bo6_zmb_c = 0;
            while (level.mp_bo6_zmb_c < level.mp_bo6_zmb_n)
            {
                nengine_store_set("bo6zmb", mp_bo6_zmb_key(level.mp_bo6_zmb_c), level.mp_bo6_zmb_saved[level.mp_bo6_zmb_c]);
                level.mp_bo6_zmb_c = level.mp_bo6_zmb_c + 1;
            }
            nengine_store_save("bo6zmb", "builds");
        }
    }
}
