#using scripts\common\callbacks;
#using scripts\common\utility;
#using scripts\mp\armor;
#using scripts\mp\common\perks\zombie\zombie_perks;
#using scripts\mp\common\utility\lui_game_event_aggregator;
#using scripts\mp\currency;
#using scripts\mp\purchasemenu;

#namespace zm_cp_custom_perks;

autoexec cp_custom_perks_init()
{
    setdvar( @"bo7_cp_debug_state", "manager_autoexec" );
    setdvar( @"bo7_cp_handler_build", "coop_augments_hud_registration_v107" );
    setdvar( @"bo7_cp_perk_manifest_ready", "0" );
    setdvar( @"bo7_cp_registered_perks", "v1:" );
    print( "Custom perk manager autoexec reached" );
    setdvar( @"bo7_cp_hud_slot_0", "" );
    setdvar( @"bo7_cp_hud_slot_1", "" );
    setdvar( @"bo7_cp_hud_slot_2", "" );
    setdvar( @"bo7_cp_hud_slot_3", "" );
    level.cp_defs = [];
    level.cp_code_to_id = [];
    level.cp_registered_perks = [];
    level.cp_register = &cp_register;
    level.cp_register_native = &cp_register_native;
    level.cp_damage_mods = [];
    level.cp_register_damage_mod = &cp_register_damage_mod;
    level.cp_preview_health_damage = &cp_preview_health_damage;
    level.cp_get_pick = &cp_get_pick;
    level.cp_has = &cp_has;
    level.cp_give = &cp_give;
    level.cp_take = &cp_take;
    lui_game_event_aggregator::registeronluieventcallback( &on_wunderfizz_purchase );
    level callback::add( #"player_spawned", &cp_gold_on_spawn );
    setdvar( @"bo7_cp_debug_state", "listener_registered" );
    logstring( "Custom Wonderfizz listener registered during manager startup" );
    level callback::add( #"player_spawned", &cp_sync_manifest_on_spawn );
    level thread cp_native_toggle_init();
    level thread cp_initialize();
    level thread cp_install_damage_hook();
    level thread cp_hud_snapshot_watch();
}

function cp_register_damage_mod( fn )
{
    level.cp_damage_mods[ level.cp_damage_mods.size ] = fn;
}

function cp_install_damage_hook()
{
    level endon( #"game_ended" );
    level utility::flag_wait_all( "StartGameTypeCallbackFinished", "zombie_perks_init_complete" );

    n_tries = 0;

    while ( !utility::issharedfuncdefined( #"zombie", #"hash_555f057b4e2d44f8" ) && n_tries < 100 )
    {
        wait 0.1;
        n_tries++;
    }

    if ( isdefined( level.cp_damage_hook_installed ) )
    {
        return;
    }

    level.cp_damage_hook_installed = 1;
    level.cp_base_damage_mod = undefined;

    if ( utility::issharedfuncdefined( #"zombie", #"hash_555f057b4e2d44f8" ) )
    {
        level.cp_base_damage_mod = utility::getsharedfunc( #"zombie", #"hash_555f057b4e2d44f8" );
    }

    utility::registersharedfunc( #"zombie", #"hash_555f057b4e2d44f8", &cp_player_damage_mod );
    setdvar( @"bo7_cp_damage_hook", isdefined( level.cp_base_damage_mod ) ? "wrapped" : "installed (no base)" );
}

function cp_player_damage_mod( sparams )
{
    n_damage = sparams.idamage;

    if ( isdefined( level.cp_base_damage_mod ) )
    {
        n_damage = self [[ level.cp_base_damage_mod ]]( sparams );
    }

    if ( !isplayer( self ) || !isdefined( n_damage ) )
    {
        return n_damage;
    }

    foreach ( fn in level.cp_damage_mods )
    {
        n_damage = self [[ fn ]]( sparams, n_damage );
    }

    return n_damage;
}

function cp_preview_health_damage( sparams, n_damage )
{
    if ( ( self.armorhealth ?? 0 ) <= 0 )
    {
        return n_damage;
    }

    [ n_health_damage, n_light_armor_damage ] = armor::function_4875d04d69b22ae( sparams.eattacker, sparams.einflictor, self, n_damage, sparams.objweapon, sparams.smeansofdeath, sparams.shitloc, sparams.idflags, sparams.var_cdd29ad5d1362c2, sparams.unmodifieddamage, sparams.partname, 1 );
    return n_health_damage ?? n_damage;
}

function cp_initialize()
{
    level endon( #"game_ended" );
    print( "Custom perk manager initialization started" );

    level utility::flag_wait( "StartGameTypeCallbackFinished" );

    if ( !level.zombie_perks_in_use )
    {
        setdvar( @"bo7_cp_registered_perks", "v1:" );
        setdvar( @"bo7_cp_perk_manifest_ready", "1" );
        logstring( "Custom perk manager skipped: Zombies perks are disabled" );
        return;
    }

    level utility::flag_wait_all(
        "zombie_perks_init_complete",
        "perk_machines_ready"
    );
    print( "Custom perk manager initialization flags passed" );

    callback::add( "zm_perk_obtained", &cp_update_overflow_perks );
    callback::add( "zm_perk_lost", &cp_update_overflow_perks );

    callback::callback( "custom_perks_register", {} );
    wait 0.1;

    foreach ( id, def in level.cp_defs )
    {
        cp_register_native( id, def );
    }

    manifest = "v1:";
    delimiter = "";
    foreach ( id, is_registered in level.cp_registered_perks )
    {
        if ( is_registered && isdefined( level.cp_defs[ id ] ) )
        {
            manifest = manifest + delimiter + id;
            delimiter = ",";
        }
    }
    level.cp_client_manifest = manifest;
    setdvar( @"bo7_cp_registered_perks", manifest );
    setdvar( @"bo7_cp_perk_manifest_ready", "1" );

    level.cp_custom_perks_ready = 1;
    setdvar( @"bo7_cp_debug_state", "manager_ready" );
    print( "Custom perk manager ready" );
    logstring( "Custom perk manager ready" );

    foreach ( player in level.players )
    {
        player cp_update_overflow_perks( {} );
        player cp_gold_open_sync();
        player thread cp_sync_manifest_to_client();
    }
}

function cp_update_overflow_perks( params )
{
    if ( isplayer( self ) )
    {
        self thread cp_refresh_owner_hud();
    }
}

function cp_refresh_owner_hud()
{
    self notify( "cp_owner_hud_refresh_restart" );
    self endon( "cp_owner_hud_refresh_restart" );
    self endon( #"disconnect" );
    level endon( #"game_ended" );
    wait 0.05;
    self cp_publish_owner_hud();
}

function cp_publish_owner_hud()
{
    if ( !isplayer( self ) )
    {
        return;
    }
    state = "v1:";
    delimiter = "";
    all_state = "v1:";
    all_delimiter = "";

    if ( isdefined( self.perks_active ) )
    {
        for ( i = 0; i < self.perks_active.size; i++ )
        {
            perk = self.perks_active[ i ];
            if ( isdefined( perk ) && perk != "specialty_choice" )
            {
                all_state = all_state + all_delimiter + perk;
                all_delimiter = ",";

                if ( i >= 16 )
                {
                    state = state + delimiter + perk;
                    delimiter = ",";
                }
            }
        }
    }

    owner_signature = all_state;
    owner_signature = owner_signature + ":" + ( self zombie_perks::has_perk( "specialty_vitality" ) ? "1" : "0" );
    owner_signature = owner_signature + ":" + ( self zombie_perks::has_perk( "specialty_electric_cherry" ) ? "1" : "0" );
    owner_signature = owner_signature + ":" + ( self zombie_perks::has_perk( "specialty_tortoise" ) ? "1" : "0" );
    owner_signature = owner_signature + ":" + ( self zombie_perks::has_perk( "specialty_bandolier" ) ? "1" : "0" );
    owner_signature = owner_signature + ":" + ( self zombie_perks::has_perk( "specialty_gautys_gold" ) ? "1" : "0" );
    owner_signature = owner_signature + ":" + ( self zombie_perks::has_perk( "specialty_jug2" ) ? "1" : "0" );
    if ( isdefined( self.cp_last_owner_hud_signature ) && self.cp_last_owner_hud_signature == owner_signature )
    {
        return;
    }
    self.cp_last_owner_hud_signature = owner_signature;

    self setclientdvar( @"bo7_cp_client_overflow_perks", state );
    self setclientdvar( @"bo7_cp_client_all_perks", all_state );
    owned_vitality = self zombie_perks::has_perk( "specialty_vitality" );
    self setclientdvar( @"bo7_cp_client_owned_vitality", owned_vitality ? "1" : "0" );
    owned_electric_cherry = self zombie_perks::has_perk( "specialty_electric_cherry" );
    self setclientdvar( @"bo7_cp_client_owned_electric_cherry", owned_electric_cherry ? "1" : "0" );
    owned_tortoise = self zombie_perks::has_perk( "specialty_tortoise" );
    self setclientdvar( @"bo7_cp_client_owned_tortoise", owned_tortoise ? "1" : "0" );
    owned_bandolier = self zombie_perks::has_perk( "specialty_bandolier" );
    self setclientdvar( @"bo7_cp_client_owned_bandolier", owned_bandolier ? "1" : "0" );
    owned_gautys_gold = self zombie_perks::has_perk( "specialty_gautys_gold" );
    self setclientdvar( @"bo7_cp_client_owned_gautys_gold", owned_gautys_gold ? "1" : "0" );
    owned_jug2 = self zombie_perks::has_perk( "specialty_jug2" );
    self setclientdvar( @"bo7_cp_client_owned_jug2", owned_jug2 ? "1" : "0" );
    self setclientdvar( @"bo7_cp_client_hud_ready", "1" );
}

function cp_register( def )
{
    if ( !isarray( def ) || !isdefined( def[ "id" ] ) || !isdefined( def[ "code" ] ) )
    {
        logstring( "Custom perk registration rejected: definition needs id and code" );
        return false;
    }

    id = def[ "id" ];
    code = int( def[ "code" ] );

    if ( !isstring( id ) || code < 1 || code > 99 )
    {
        logstring( "Custom perk registration rejected: invalid id or code" );
        return false;
    }

    if ( isdefined( level.cp_defs[ id ] ) || isdefined( level.cp_code_to_id[ code ] ) )
    {
        logstring( "Custom perk registration rejected: duplicate id or code for " + id );
        return false;
    }

    def[ "code" ] = code;
    def[ "ref" ] = "specialty_" + id;
    level.cp_defs[ id ] = def;
    level.cp_code_to_id[ code ] = id;
    return true;
}

// 1 = the player switched this perk off in the menu (bo7_cp_off_<id>, saved by mp_bo6_store.gsc). A switched-off perk is not
// registered, so it is not in the registered-perk list the menus read and cannot be bought. New perks need a line here.
function cp_perk_disabled( id )
{
    return getdvarint("bo7_cp_off_" + id, 0) == 1;
}

function cp_register_native( id, def )
{
    if ( cp_perk_disabled( id ) )
    {
        logstring( "Custom perk " + id + " is switched off in the menu; not registered" );
        return;
    }

    ref = def[ "ref" ];
    drink_from = def[ "drink_from" ] ?? "specialty_juggernog";

    if ( !isdefined( level.perkbundles ) )
    {
        logstring( "Custom perk " + id + " skipped: perk bundles are unavailable" );
        return;
    }

    src = level.perkbundles[ drink_from ];

    if ( !isdefined( src ) )
    {
        logstring( "Custom perk " + id + " skipped: source perk bundle is missing" );
        return;
    }

    if ( !isdefined( level._custom_perks ) )
    {
        level._custom_perks = [];
    }

    if ( isdefined( level._custom_perks[ ref ] ) )
    {
        logstring( "Custom perk " + id + " skipped: perk ref already exists" );
        return;
    }

    custom_bundle = spawnstruct();
    custom_bundle.name = def[ "name" ] ?? id;
    custom_bundle.description = def[ "description" ] ?? "";
    custom_bundle.var_4f05ecd6a02ee78c = src.var_4f05ecd6a02ee78c;
    custom_bundle.zmperkcost = src.zmperkcost;
    custom_bundle.zmperkmachineradiusoverride = src.zmperkmachineradiusoverride;
    custom_bundle.zmperkscriptable = src.zmperkscriptable;
    custom_bundle.zmperkgesture = src.zmperkgesture;
    custom_bundle.zmperkhinticon = def[ "icon_material" ] ?? src.zmperkhinticon;
    custom_bundle.zmperksound = src.zmperksound;
    custom_bundle.var_ccd5d2ff97067631 = src.var_ccd5d2ff97067631 ?? undefined;
    custom_bundle.var_8cded1959bcc76fd = src.var_8cded1959bcc76fd ?? undefined;
    custom_bundle.var_e77b4be2fc4d857f = src.var_e77b4be2fc4d857f ?? undefined;
    custom_bundle.zombiesperk = 1;
    custom_bundle.showninmenu = 1;
    level.perkbundles[ ref ] = custom_bundle;

    if ( isdefined( level.zmperkidbyref ) && isdefined( level.zmperkidbyref[ drink_from ] ) )
    {
        if ( id == "vitality" || id == "bandolier" || id == "tortoise" || id == "gautys_gold" || id == "jug2" || id == "electric_cherry" || id == "blaze_phase" )
        {
            hud_perk_id = cp_allocate_hud_perk_id();
            if ( hud_perk_id > 0 )
            {
                level.zmperkidbyref[ ref ] = hud_perk_id;
                setdvar( "bo7_cp_hud_id_" + id, "" + hud_perk_id );
                logstring( "Custom perk " + id + " assigned HUD perk ID " + hud_perk_id );
            }
            else
            {
                level.zmperkidbyref[ ref ] = level.zmperkidbyref[ drink_from ];
                logstring( "Custom perk " + id + " has no free HUD perk ID; using placeholder ID" );
            }
        }
        else
        {
            level.zmperkidbyref[ ref ] = level.zmperkidbyref[ drink_from ];
        }
    }

    str_currency = currency::get_perk_machine_currency( drink_from );
    n_fixed_cost = def[ "price" ] ?? src.zmperkcost;
    func_give = def[ "on_give" ];
    func_take = def[ "on_take" ];

    if ( !isdefined( func_give ) )
    {
        func_give = &cp_noop_give;
    }

    if ( !isdefined( func_take ) )
    {
        func_take = &cp_noop_take;
    }
    level thread zombie_perks::enable_perk_for_level(
        ref,
        str_currency,
        n_fixed_cost,
        func_give,
        func_take,
        1,
        1
    );
    level.cp_registered_perks[ id ] = 1;
    logstring( "Custom perk " + id + " queued for the Zombies perk manager" );
}

function cp_allocate_hud_perk_id()
{
    for ( candidate = 31; candidate > 0; candidate-- )
    {
        b_used = 0;
        foreach ( perk_ref, perk_id in level.zmperkidbyref )
        {
            if ( perk_id == candidate )
            {
                b_used = 1;
                break;
            }
        }

        if ( !b_used )
        {
            return candidate;
        }
    }

    return 0;
}

function cp_noop_give()
{
}

function cp_noop_take( b_pause, str_perk, str_result, n_slot )
{
}

function cp_has( player, id )
{
    if ( !isdefined( player ) || !isdefined( level.cp_defs[ id ] ) )
    {
        return false;
    }

    return player zombie_perks::has_perk( level.cp_defs[ id ][ "ref" ] );
}

function cp_give( id )
{
    if (cp_perk_disabled(id)) return;
    if ( !isdefined( level.cp_defs[ id ] ) )
    {
        logstring( "Custom perk give rejected: unknown id " + id );
        return;
    }

    zombie_perks::give_perk( level.cp_defs[ id ][ "ref" ], 1 );
}

function cp_take( id )
{
    if ( !isdefined( level.cp_defs[ id ] ) )
    {
        logstring( "Custom perk take rejected: unknown id " + id );
        return;
    }

    zombie_perks::take_perk( level.cp_defs[ id ][ "ref" ] );
}

function on_wunderfizz_purchase( channel, menuitemindex )
{
    if ( self cp_receive_generated_jug2( channel, menuitemindex ) ) return; // generated coop jug2


    if ( self cp_receive_generated_tortoise( channel, menuitemindex ) ) return; 

    if ( self cp_receive_generated_gautys_gold( channel, menuitemindex ) ) return; 

    if ( self cp_receive_generated_bandolier( channel, menuitemindex ) ) return; 

    if ( self cp_receive_generated_electric_cherry( channel, menuitemindex ) ) return; 

    value_is_string = false;
    numeric_match_4021 = false;
    if ( isdefined( menuitemindex ) )
    {
        value_is_string = isstring( menuitemindex );
        numeric_match_4021 = menuitemindex == 4021;
    }
    event_diagnostic = "build=v102 channel=" + channel + " value=" + menuitemindex + " isstring=" + value_is_string + " eq4021=" + numeric_match_4021 + " sender_isplayer=" + isplayer( self );
    if ( !isdefined( level.cp_gold_last_event_diagnostic ) || level.cp_gold_last_event_diagnostic != event_diagnostic )
    {
        level.cp_gold_last_event_diagnostic = event_diagnostic;
        logstring( "COOP GOLD RX " + event_diagnostic );
        setdvar( @"bo7_cp_gold_event_debug", event_diagnostic );
    }
    if ( !isdefined( channel ) || !isdefined( menuitemindex ) )
    {
        return;
    }

    if ( channel != "custom_perk_choice_purchase" && channel != "perk_choice_purchase" )
    {
        return;
    }

    if ( menuitemindex == 9000 || ( isstring( menuitemindex ) && menuitemindex == "9000" ) )
    {
        if ( isplayer( self ) )
        {
            self.cp_hud_slot = 0;
            self.cp_hud_watch_snapshot = undefined;
            self cp_publish_slot_perks();
        }
        return;
    }
    if ( menuitemindex == 9001 || ( isstring( menuitemindex ) && menuitemindex == "9001" ) )
    {
        if ( isplayer( self ) )
        {
            self.cp_hud_slot = 1;
            self.cp_hud_watch_snapshot = undefined;
            self cp_publish_slot_perks();
        }
        return;
    }
    if ( menuitemindex == 9002 || ( isstring( menuitemindex ) && menuitemindex == "9002" ) )
    {
        if ( isplayer( self ) )
        {
            self.cp_hud_slot = 2;
            self.cp_hud_watch_snapshot = undefined;
            self cp_publish_slot_perks();
        }
        return;
    }
    if ( menuitemindex == 9003 || ( isstring( menuitemindex ) && menuitemindex == "9003" ) )
    {
        if ( isplayer( self ) )
        {
            self.cp_hud_slot = 3;
            self.cp_hud_watch_snapshot = undefined;
            self cp_publish_slot_perks();
        }
        return;
    }

    if ( menuitemindex == 5000 || ( isstring( menuitemindex ) && menuitemindex == "5000" ) )
    {
        self cp_receive_vitality_pick( channel, 5000 );
        return;
    }
    if ( menuitemindex == 5001 || ( isstring( menuitemindex ) && menuitemindex == "5001" ) )
    {
        self cp_receive_vitality_pick( channel, 5001 );
        return;
    }
    if ( menuitemindex == 5002 || ( isstring( menuitemindex ) && menuitemindex == "5002" ) )
    {
        self cp_receive_vitality_pick( channel, 5002 );
        return;
    }
    if ( menuitemindex == 5010 || ( isstring( menuitemindex ) && menuitemindex == "5010" ) )
    {
        self cp_receive_vitality_pick( channel, 5010 );
        return;
    }
    if ( menuitemindex == 5011 || ( isstring( menuitemindex ) && menuitemindex == "5011" ) )
    {
        self cp_receive_vitality_pick( channel, 5011 );
        return;
    }
    if ( menuitemindex == 5012 || ( isstring( menuitemindex ) && menuitemindex == "5012" ) )
    {
        self cp_receive_vitality_pick( channel, 5012 );
        return;
    }
    if ( menuitemindex == 5020 || ( isstring( menuitemindex ) && menuitemindex == "5020" ) )
    {
        self cp_receive_vitality_pick( channel, 5020 );
        return;
    }
    if ( menuitemindex == 5021 || ( isstring( menuitemindex ) && menuitemindex == "5021" ) )
    {
        self cp_receive_vitality_pick( channel, 5021 );
        return;
    }
    if ( menuitemindex == 5022 || ( isstring( menuitemindex ) && menuitemindex == "5022" ) )
    {
        self cp_receive_vitality_pick( channel, 5022 );
        return;
    }
    if ( menuitemindex == 5100 || ( isstring( menuitemindex ) && menuitemindex == "5100" ) )
    {
        self cp_receive_vitality_pick( channel, 5100 );
        return;
    }
    if ( menuitemindex == 5102 || ( isstring( menuitemindex ) && menuitemindex == "5102" ) )
    {
        self cp_receive_vitality_pick( channel, 5102 );
        return;
    }
    if ( menuitemindex == 5110 || ( isstring( menuitemindex ) && menuitemindex == "5110" ) )
    {
        self cp_receive_vitality_pick( channel, 5110 );
        return;
    }
    if ( menuitemindex == 5112 || ( isstring( menuitemindex ) && menuitemindex == "5112" ) )
    {
        self cp_receive_vitality_pick( channel, 5112 );
        return;
    }
    if ( menuitemindex == 5120 || ( isstring( menuitemindex ) && menuitemindex == "5120" ) )
    {
        self cp_receive_vitality_pick( channel, 5120 );
        return;
    }
    if ( menuitemindex == 5122 || ( isstring( menuitemindex ) && menuitemindex == "5122" ) )
    {
        self cp_receive_vitality_pick( channel, 5122 );
        return;
    }
    if ( menuitemindex == 5200 || ( isstring( menuitemindex ) && menuitemindex == "5200" ) )
    {
        self cp_receive_vitality_pick( channel, 5200 );
        return;
    }
    if ( menuitemindex == 5201 || ( isstring( menuitemindex ) && menuitemindex == "5201" ) )
    {
        self cp_receive_vitality_pick( channel, 5201 );
        return;
    }
    if ( menuitemindex == 5210 || ( isstring( menuitemindex ) && menuitemindex == "5210" ) )
    {
        self cp_receive_vitality_pick( channel, 5210 );
        return;
    }
    if ( menuitemindex == 5211 || ( isstring( menuitemindex ) && menuitemindex == "5211" ) )
    {
        self cp_receive_vitality_pick( channel, 5211 );
        return;
    }
    if ( menuitemindex == 5220 || ( isstring( menuitemindex ) && menuitemindex == "5220" ) )
    {
        self cp_receive_vitality_pick( channel, 5220 );
        return;
    }
    if ( menuitemindex == 5221 || ( isstring( menuitemindex ) && menuitemindex == "5221" ) )
    {
        self cp_receive_vitality_pick( channel, 5221 );
        return;
    }
    if ( menuitemindex == 6000 || ( isstring( menuitemindex ) && menuitemindex == "6000" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6000 );
        return;
    }
    if ( menuitemindex == 6001 || ( isstring( menuitemindex ) && menuitemindex == "6001" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6001 );
        return;
    }
    if ( menuitemindex == 6002 || ( isstring( menuitemindex ) && menuitemindex == "6002" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6002 );
        return;
    }
    if ( menuitemindex == 6003 || ( isstring( menuitemindex ) && menuitemindex == "6003" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6003 );
        return;
    }
    if ( menuitemindex == 6010 || ( isstring( menuitemindex ) && menuitemindex == "6010" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6010 );
        return;
    }
    if ( menuitemindex == 6011 || ( isstring( menuitemindex ) && menuitemindex == "6011" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6011 );
        return;
    }
    if ( menuitemindex == 6012 || ( isstring( menuitemindex ) && menuitemindex == "6012" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6012 );
        return;
    }
    if ( menuitemindex == 6013 || ( isstring( menuitemindex ) && menuitemindex == "6013" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6013 );
        return;
    }
    if ( menuitemindex == 6020 || ( isstring( menuitemindex ) && menuitemindex == "6020" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6020 );
        return;
    }
    if ( menuitemindex == 6021 || ( isstring( menuitemindex ) && menuitemindex == "6021" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6021 );
        return;
    }
    if ( menuitemindex == 6022 || ( isstring( menuitemindex ) && menuitemindex == "6022" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6022 );
        return;
    }
    if ( menuitemindex == 6023 || ( isstring( menuitemindex ) && menuitemindex == "6023" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6023 );
        return;
    }
    if ( menuitemindex == 6100 || ( isstring( menuitemindex ) && menuitemindex == "6100" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6100 );
        return;
    }
    if ( menuitemindex == 6102 || ( isstring( menuitemindex ) && menuitemindex == "6102" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6102 );
        return;
    }
    if ( menuitemindex == 6103 || ( isstring( menuitemindex ) && menuitemindex == "6103" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6103 );
        return;
    }
    if ( menuitemindex == 6110 || ( isstring( menuitemindex ) && menuitemindex == "6110" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6110 );
        return;
    }
    if ( menuitemindex == 6112 || ( isstring( menuitemindex ) && menuitemindex == "6112" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6112 );
        return;
    }
    if ( menuitemindex == 6113 || ( isstring( menuitemindex ) && menuitemindex == "6113" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6113 );
        return;
    }
    if ( menuitemindex == 6120 || ( isstring( menuitemindex ) && menuitemindex == "6120" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6120 );
        return;
    }
    if ( menuitemindex == 6122 || ( isstring( menuitemindex ) && menuitemindex == "6122" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6122 );
        return;
    }
    if ( menuitemindex == 6123 || ( isstring( menuitemindex ) && menuitemindex == "6123" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6123 );
        return;
    }
    if ( menuitemindex == 6200 || ( isstring( menuitemindex ) && menuitemindex == "6200" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6200 );
        return;
    }
    if ( menuitemindex == 6201 || ( isstring( menuitemindex ) && menuitemindex == "6201" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6201 );
        return;
    }
    if ( menuitemindex == 6203 || ( isstring( menuitemindex ) && menuitemindex == "6203" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6203 );
        return;
    }
    if ( menuitemindex == 6210 || ( isstring( menuitemindex ) && menuitemindex == "6210" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6210 );
        return;
    }
    if ( menuitemindex == 6211 || ( isstring( menuitemindex ) && menuitemindex == "6211" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6211 );
        return;
    }
    if ( menuitemindex == 6213 || ( isstring( menuitemindex ) && menuitemindex == "6213" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6213 );
        return;
    }
    if ( menuitemindex == 6220 || ( isstring( menuitemindex ) && menuitemindex == "6220" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6220 );
        return;
    }
    if ( menuitemindex == 6221 || ( isstring( menuitemindex ) && menuitemindex == "6221" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6221 );
        return;
    }
    if ( menuitemindex == 6223 || ( isstring( menuitemindex ) && menuitemindex == "6223" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6223 );
        return;
    }
    if ( menuitemindex == 6300 || ( isstring( menuitemindex ) && menuitemindex == "6300" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6300 );
        return;
    }
    if ( menuitemindex == 6301 || ( isstring( menuitemindex ) && menuitemindex == "6301" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6301 );
        return;
    }
    if ( menuitemindex == 6302 || ( isstring( menuitemindex ) && menuitemindex == "6302" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6302 );
        return;
    }
    if ( menuitemindex == 6310 || ( isstring( menuitemindex ) && menuitemindex == "6310" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6310 );
        return;
    }
    if ( menuitemindex == 6311 || ( isstring( menuitemindex ) && menuitemindex == "6311" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6311 );
        return;
    }
    if ( menuitemindex == 6312 || ( isstring( menuitemindex ) && menuitemindex == "6312" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6312 );
        return;
    }
    if ( menuitemindex == 6320 || ( isstring( menuitemindex ) && menuitemindex == "6320" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6320 );
        return;
    }
    if ( menuitemindex == 6321 || ( isstring( menuitemindex ) && menuitemindex == "6321" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6321 );
        return;
    }
    if ( menuitemindex == 6322 || ( isstring( menuitemindex ) && menuitemindex == "6322" ) )
    {
        self cp_receive_electric_cherry_pick( channel, 6322 );
        return;
    }
    if ( menuitemindex == 7000 || ( isstring( menuitemindex ) && menuitemindex == "7000" ) )
    {
        self cp_receive_tortoise_pick( channel, 7000 );
        return;
    }
    if ( menuitemindex == 7001 || ( isstring( menuitemindex ) && menuitemindex == "7001" ) )
    {
        self cp_receive_tortoise_pick( channel, 7001 );
        return;
    }
    if ( menuitemindex == 7010 || ( isstring( menuitemindex ) && menuitemindex == "7010" ) )
    {
        self cp_receive_tortoise_pick( channel, 7010 );
        return;
    }
    if ( menuitemindex == 7011 || ( isstring( menuitemindex ) && menuitemindex == "7011" ) )
    {
        self cp_receive_tortoise_pick( channel, 7011 );
        return;
    }
    if ( menuitemindex == 7020 || ( isstring( menuitemindex ) && menuitemindex == "7020" ) )
    {
        self cp_receive_tortoise_pick( channel, 7020 );
        return;
    }
    if ( menuitemindex == 7021 || ( isstring( menuitemindex ) && menuitemindex == "7021" ) )
    {
        self cp_receive_tortoise_pick( channel, 7021 );
        return;
    }
    if ( menuitemindex == 7100 || ( isstring( menuitemindex ) && menuitemindex == "7100" ) )
    {
        self cp_receive_tortoise_pick( channel, 7100 );
        return;
    }
    if ( menuitemindex == 7110 || ( isstring( menuitemindex ) && menuitemindex == "7110" ) )
    {
        self cp_receive_tortoise_pick( channel, 7110 );
        return;
    }
    if ( menuitemindex == 7120 || ( isstring( menuitemindex ) && menuitemindex == "7120" ) )
    {
        self cp_receive_tortoise_pick( channel, 7120 );
        return;
    }
    if ( menuitemindex == 8000 || ( isstring( menuitemindex ) && menuitemindex == "8000" ) )
    {
        self cp_receive_bandolier_pick( channel, 8000 );
        return;
    }
    if ( menuitemindex == 8001 || ( isstring( menuitemindex ) && menuitemindex == "8001" ) )
    {
        self cp_receive_bandolier_pick( channel, 8001 );
        return;
    }
    if ( menuitemindex == 8002 || ( isstring( menuitemindex ) && menuitemindex == "8002" ) )
    {
        self cp_receive_bandolier_pick( channel, 8002 );
        return;
    }
    if ( menuitemindex == 8010 || ( isstring( menuitemindex ) && menuitemindex == "8010" ) )
    {
        self cp_receive_bandolier_pick( channel, 8010 );
        return;
    }
    if ( menuitemindex == 8011 || ( isstring( menuitemindex ) && menuitemindex == "8011" ) )
    {
        self cp_receive_bandolier_pick( channel, 8011 );
        return;
    }
    if ( menuitemindex == 8012 || ( isstring( menuitemindex ) && menuitemindex == "8012" ) )
    {
        self cp_receive_bandolier_pick( channel, 8012 );
        return;
    }
    if ( menuitemindex == 8020 || ( isstring( menuitemindex ) && menuitemindex == "8020" ) )
    {
        self cp_receive_bandolier_pick( channel, 8020 );
        return;
    }
    if ( menuitemindex == 8021 || ( isstring( menuitemindex ) && menuitemindex == "8021" ) )
    {
        self cp_receive_bandolier_pick( channel, 8021 );
        return;
    }
    if ( menuitemindex == 8022 || ( isstring( menuitemindex ) && menuitemindex == "8022" ) )
    {
        self cp_receive_bandolier_pick( channel, 8022 );
        return;
    }
    if ( menuitemindex == 8100 || ( isstring( menuitemindex ) && menuitemindex == "8100" ) )
    {
        self cp_receive_bandolier_pick( channel, 8100 );
        return;
    }
    if ( menuitemindex == 8102 || ( isstring( menuitemindex ) && menuitemindex == "8102" ) )
    {
        self cp_receive_bandolier_pick( channel, 8102 );
        return;
    }
    if ( menuitemindex == 8110 || ( isstring( menuitemindex ) && menuitemindex == "8110" ) )
    {
        self cp_receive_bandolier_pick( channel, 8110 );
        return;
    }
    if ( menuitemindex == 8112 || ( isstring( menuitemindex ) && menuitemindex == "8112" ) )
    {
        self cp_receive_bandolier_pick( channel, 8112 );
        return;
    }
    if ( menuitemindex == 8120 || ( isstring( menuitemindex ) && menuitemindex == "8120" ) )
    {
        self cp_receive_bandolier_pick( channel, 8120 );
        return;
    }
    if ( menuitemindex == 8122 || ( isstring( menuitemindex ) && menuitemindex == "8122" ) )
    {
        self cp_receive_bandolier_pick( channel, 8122 );
        return;
    }
    if ( menuitemindex == 8200 || ( isstring( menuitemindex ) && menuitemindex == "8200" ) )
    {
        self cp_receive_bandolier_pick( channel, 8200 );
        return;
    }
    if ( menuitemindex == 8201 || ( isstring( menuitemindex ) && menuitemindex == "8201" ) )
    {
        self cp_receive_bandolier_pick( channel, 8201 );
        return;
    }
    if ( menuitemindex == 8210 || ( isstring( menuitemindex ) && menuitemindex == "8210" ) )
    {
        self cp_receive_bandolier_pick( channel, 8210 );
        return;
    }
    if ( menuitemindex == 8211 || ( isstring( menuitemindex ) && menuitemindex == "8211" ) )
    {
        self cp_receive_bandolier_pick( channel, 8211 );
        return;
    }
    if ( menuitemindex == 8220 || ( isstring( menuitemindex ) && menuitemindex == "8220" ) )
    {
        self cp_receive_bandolier_pick( channel, 8220 );
        return;
    }
    if ( menuitemindex == 8221 || ( isstring( menuitemindex ) && menuitemindex == "8221" ) )
    {
        self cp_receive_bandolier_pick( channel, 8221 );
        return;
    }
    if ( menuitemindex == 4000 || ( isstring( menuitemindex ) && menuitemindex == "4000" ) )
    {
        self cp_receive_gold_pick( channel, 4000 );
        return;
    }
    if ( menuitemindex == 4001 || ( isstring( menuitemindex ) && menuitemindex == "4001" ) )
    {
        self cp_receive_gold_pick( channel, 4001 );
        return;
    }
    if ( menuitemindex == 4010 || ( isstring( menuitemindex ) && menuitemindex == "4010" ) )
    {
        self cp_receive_gold_pick( channel, 4010 );
        return;
    }
    if ( menuitemindex == 4011 || ( isstring( menuitemindex ) && menuitemindex == "4011" ) )
    {
        self cp_receive_gold_pick( channel, 4011 );
        return;
    }
    if ( menuitemindex == 4020 || ( isstring( menuitemindex ) && menuitemindex == "4020" ) )
    {
        self cp_receive_gold_pick( channel, 4020 );
        return;
    }
    if ( menuitemindex == 4021 || ( isstring( menuitemindex ) && menuitemindex == "4021" ) )
    {
        self cp_receive_gold_pick( channel, 4021 );
        return;
    }
    if ( menuitemindex == 4100 || ( isstring( menuitemindex ) && menuitemindex == "4100" ) )
    {
        self cp_receive_gold_pick( channel, 4100 );
        return;
    }
    if ( menuitemindex == 4110 || ( isstring( menuitemindex ) && menuitemindex == "4110" ) )
    {
        self cp_receive_gold_pick( channel, 4110 );
        return;
    }
    if ( menuitemindex == 4120 || ( isstring( menuitemindex ) && menuitemindex == "4120" ) )
    {
        self cp_receive_gold_pick( channel, 4120 );
        return;
    }
    logstring( "Custom Wonderfizz event received: " + channel + " index " + menuitemindex );

    if ( menuitemindex == 1778 || ( isstring( menuitemindex ) && menuitemindex == "1778" ) )
    {
        self thread purchase_custom_perk( "bandolier", "specialty_bandolier" );
    }
    else if ( menuitemindex == 1773 || ( isstring( menuitemindex ) && menuitemindex == "1773" ) )
    {
        self thread purchase_custom_perk( "tortoise", "specialty_tortoise" );
    }
    else if ( menuitemindex == 1782 || ( isstring( menuitemindex ) && menuitemindex == "1782" ) )
    {
        self thread purchase_custom_perk( "gautys_gold", "specialty_gautys_gold" );
    }
    else if ( menuitemindex == 1771 || ( isstring( menuitemindex ) && menuitemindex == "1771" ) )
    {
        self thread purchase_custom_perk( "jug2", "specialty_jug2" );
    }
    else if ( menuitemindex == 1772 || ( isstring( menuitemindex ) && menuitemindex == "1772" ) )
    {
        self thread purchase_custom_perk( "electric_cherry", "specialty_electric_cherry" );
    }

    else
    {
        setdvar( @"bo7_cp_debug_state", "reject:unmapped:" + menuitemindex );
        logstring( "Custom Wonderfizz event rejected: unmapped index " + menuitemindex );
    }
}

function purchase_custom_perk( id, ref )
{
    level endon( #"game_ended" );
    setdvar( @"bo7_cp_debug_state", "mapped:" + id );

    if ( !isdefined( level.perkbundles ) || !isdefined( level.perkbundles[ ref ] ) ||
         !isdefined( level._custom_perks ) || !isdefined( level._custom_perks[ ref ] ) )
    {
        setdvar( @"bo7_cp_debug_state", "reject:not_registered:" + id );
        logstring( "Custom Wonderfizz purchase rejected: native perk registration missing for " + id );
        return;
    }

    print( "Custom Wonderfizz purchase received for " + id );

    if ( self zombie_perks::has_perk( ref ) )
    {
        setdvar( @"bo7_cp_debug_state", "reject:already_owned:" + id );
        logstring( "Custom Wonderfizz purchase rejected: perk already owned for " + id );
        return;
    }

    if ( !isdefined( self.s_perk_choice_machine ) )
    {
        setdvar( @"bo7_cp_debug_state", "reject:missing_machine:" + id );
        logstring( "Custom Wonderfizz purchase rejected: machine state missing for " + id );
        return;
    }

    perk_cost = self zombie_perks::function_77331fd62580dd0a();
    str_currency = currency::get_perk_machine_currency( "specialty_juggernog" );

    setdvar( @"bo7_cp_debug_state", "purchase_attempt:" + id );
    if ( !self currency::attempt_purchase( str_currency, perk_cost, 1, undefined, #"perk", ref ) )
    {
        setdvar( @"bo7_cp_debug_state", "reject:insufficient_currency:" + id );
        logstring( "Custom Wonderfizz purchase denied: insufficient currency for " + id );
        purchasemenu::function_93f934ea2f1c06f8( 3 );
        return;
    }
    setdvar( @"bo7_cp_debug_state", "paid:" + id );

    if ( isdefined( level.gametypebundle.var_d2a7b8fafa40d741 ) && level.gametypebundle.var_d2a7b8fafa40d741 > 0 )
    {
        if ( !isdefined( self.total_purchased_perks ) )
        {
            self.total_purchased_perks = 0;
        }

        if ( !isdefined( self.perkspurchased ) )
        {
            self.perkspurchased = [];
        }

        if ( !isdefined( level.var_af8e5ce115d7696f ) )
        {
            level.var_af8e5ce115d7696f = 0;
        }

        self.total_purchased_perks++;
        self.perkspurchased[ ref ] = 1;
        level.var_af8e5ce115d7696f++;
        level notify( #"perk_purchased" );
        n_perk_purchased_threshold = level.gametypebundle.var_d2a7b8fafa40d741 + level.players.size;

        if ( level.var_af8e5ce115d7696f >= n_perk_purchased_threshold )
        {
            level.var_865fa84b8f7cc220 = 1;
        }
    }

    b_playing_gesture = 0;
    if ( !self isgestureplaying() )
    {
        gesture = level._custom_perks[ ref ].perk_bottle_weapon;
        if ( isdefined( gesture ) )
        {
            self thread zombie_perks::play_perk_drinking_gesture( gesture );
            b_playing_gesture = 1;
        }
    }

    if ( isdefined( self.s_perk_choice_machine ) &&
         isdefined( self.s_perk_choice_machine.mdl_perk_machine ) )
    {
        paramsused = spawnstruct();
        paramsused.perk_machine = self.s_perk_choice_machine.mdl_perk_machine;
        paramsused.perk = ref;
        callback::callback( "zm_perk_machine_used", paramsused );
    }

    zombie_perks::give_perk( ref, 1, b_playing_gesture );
    setdvar( @"bo7_cp_debug_state", "give_called:" + id );

    paramspurchased = spawnstruct();
    paramspurchased.perkref = ref;
    paramspurchased.cost = perk_cost;
    paramspurchased.currency = str_currency;
    paramspurchased.source = #"wunderfizz";
    callback::callback( "zm_perk_purchased", paramspurchased );

    purchasemenu::function_93f934ea2f1c06f8( 1 );
    self notify( #"wunderfizz_purchase" );
    setdvar( @"bo7_cp_debug_state", "complete:" + id );
    logstring( "Custom Wonderfizz purchase completed for " + id );
}

function cp_sync_manifest_on_spawn( params )
{
    if ( isplayer( self ) && level.zombie_perks_in_use )
    {
        self thread cp_sync_manifest_to_client();
    }
}

function cp_sync_manifest_to_client()
{
    self notify( "cp_manifest_sync_restart" );
    self endon( "cp_manifest_sync_restart" );
    self endon( #"disconnect" );
    level endon( #"game_ended" );
    attempts = 0;
    while ( !isdefined( level.cp_client_manifest ) && attempts < 300 )
    {
        wait 0.1;
        attempts++;
    }
    if ( !isdefined( level.cp_client_manifest ) )
    {
        return;
    }
    for ( resend = 0; resend < 3; resend++ )
    {
        self setclientdvar( @"bo7_cp_registered_perks", level.cp_client_manifest );
        self setclientdvar( @"bo7_cp_perk_manifest_ready", "1" );
        self thread cp_refresh_owner_hud();
        wait 1;
    }
}
function cp_gold_on_spawn( params )
{
    if ( isplayer( self ) && level.zombie_perks_in_use )
    {
        self cp_gold_open_sync();
    }
}

function cp_gold_open_sync()
{
    if ( isdefined( self.cp_gold_major ) )
    {
        self setclientdvar( @"bo7_cp_gold_pick_ack", "accepted:" + self.cp_picks["gautys_gold"] );
    }
    else
    {
        self setclientdvar( @"bo7_cp_gold_pick_ack", "pending" );
    }
}

function cp_receive_gold_pick( channel, value )
{
    if ( !isdefined( channel ) || ( channel != "perk_choice_purchase" && channel != "custom_perk_choice_purchase" ) || !isplayer( self ) || !isdefined( value ) )
    {
        return;
    }
    setdvar( @"bo7_cp_gold_transport", "received_payload=" + value );
    if ( value == 4000 || ( isstring( value ) && value == "4000" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["gautys_gold"] = 0;
        self.cp_gold_major = 0;
        self.cp_gold_minor = 0;
        self.cp_gold_bonus = 0;
        self setclientdvar( @"bo7_cp_gold_pick_ack", "accepted:0" );
        setdvar( @"bo7_cp_gold_transport", "received_pick=0 major=0 minor=0 bonus=0 literal_path=v99" );
        return;
    }
    if ( value == 4001 || ( isstring( value ) && value == "4001" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["gautys_gold"] = 1;
        self.cp_gold_major = 0;
        self.cp_gold_minor = 1;
        self.cp_gold_bonus = 0;
        self setclientdvar( @"bo7_cp_gold_pick_ack", "accepted:1" );
        setdvar( @"bo7_cp_gold_transport", "received_pick=1 major=0 minor=1 bonus=0 literal_path=v99" );
        return;
    }
    if ( value == 4010 || ( isstring( value ) && value == "4010" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["gautys_gold"] = 10;
        self.cp_gold_major = 1;
        self.cp_gold_minor = 0;
        self.cp_gold_bonus = 0;
        self setclientdvar( @"bo7_cp_gold_pick_ack", "accepted:10" );
        setdvar( @"bo7_cp_gold_transport", "received_pick=10 major=1 minor=0 bonus=0 literal_path=v99" );
        return;
    }
    if ( value == 4011 || ( isstring( value ) && value == "4011" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["gautys_gold"] = 11;
        self.cp_gold_major = 1;
        self.cp_gold_minor = 1;
        self.cp_gold_bonus = 0;
        self setclientdvar( @"bo7_cp_gold_pick_ack", "accepted:11" );
        setdvar( @"bo7_cp_gold_transport", "received_pick=11 major=1 minor=1 bonus=0 literal_path=v99" );
        return;
    }
    if ( value == 4020 || ( isstring( value ) && value == "4020" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["gautys_gold"] = 20;
        self.cp_gold_major = 2;
        self.cp_gold_minor = 0;
        self.cp_gold_bonus = 0;
        self setclientdvar( @"bo7_cp_gold_pick_ack", "accepted:20" );
        setdvar( @"bo7_cp_gold_transport", "received_pick=20 major=2 minor=0 bonus=0 literal_path=v99" );
        return;
    }
    if ( value == 4021 || ( isstring( value ) && value == "4021" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["gautys_gold"] = 21;
        self.cp_gold_major = 2;
        self.cp_gold_minor = 1;
        self.cp_gold_bonus = 0;
        self setclientdvar( @"bo7_cp_gold_pick_ack", "accepted:21" );
        setdvar( @"bo7_cp_gold_transport", "received_pick=21 major=2 minor=1 bonus=0 literal_path=v99" );
        return;
    }
    if ( value == 4100 || ( isstring( value ) && value == "4100" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["gautys_gold"] = 100;
        self.cp_gold_major = 0;
        self.cp_gold_minor = 0;
        self.cp_gold_bonus = 1;
        self setclientdvar( @"bo7_cp_gold_pick_ack", "accepted:100" );
        setdvar( @"bo7_cp_gold_transport", "received_pick=100 major=0 minor=0 bonus=1 literal_path=v99" );
        return;
    }
    if ( value == 4110 || ( isstring( value ) && value == "4110" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["gautys_gold"] = 110;
        self.cp_gold_major = 1;
        self.cp_gold_minor = 0;
        self.cp_gold_bonus = 1;
        self setclientdvar( @"bo7_cp_gold_pick_ack", "accepted:110" );
        setdvar( @"bo7_cp_gold_transport", "received_pick=110 major=1 minor=0 bonus=1 literal_path=v99" );
        return;
    }
    if ( value == 4120 || ( isstring( value ) && value == "4120" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["gautys_gold"] = 120;
        self.cp_gold_major = 2;
        self.cp_gold_minor = 0;
        self.cp_gold_bonus = 1;
        self setclientdvar( @"bo7_cp_gold_pick_ack", "accepted:120" );
        setdvar( @"bo7_cp_gold_transport", "received_pick=120 major=2 minor=0 bonus=1 literal_path=v99" );
        return;
    }
    setdvar( @"bo7_cp_gold_transport", "rejected_payload=" + value );
}

function cp_get_pick( player, id )
{
    if ( isplayer( player ) && isdefined( player.cp_picks ) && isdefined( player.cp_picks[id] ) )
    {
        return player.cp_picks[id];
    }
    return 0;
}
function cp_receive_vitality_pick( channel, value )
{
    if ( !isplayer( self ) || !isdefined( value ) || ( channel != "perk_choice_purchase" && channel != "custom_perk_choice_purchase" ) )
    {
        return;
    }
    if ( value == 5000 || ( isstring( value ) && value == "5000" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["vitality"] = 0;
        self.cp_vitality_major = 0;
        self.cp_vitality_minor = 0;
        self.cp_vitality_bonus = 0;
        self setclientdvar( @"bo7_cp_vitality_pick_ack", "accepted:0" );
        setdvar( @"bo7_cp_augments_transport", "perk=vitality pick=0 major=0 minor=0 bonus=0" );
        return;
    }
    if ( value == 5001 || ( isstring( value ) && value == "5001" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["vitality"] = 1;
        self.cp_vitality_major = 0;
        self.cp_vitality_minor = 1;
        self.cp_vitality_bonus = 0;
        self setclientdvar( @"bo7_cp_vitality_pick_ack", "accepted:1" );
        setdvar( @"bo7_cp_augments_transport", "perk=vitality pick=1 major=0 minor=1 bonus=0" );
        return;
    }
    if ( value == 5002 || ( isstring( value ) && value == "5002" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["vitality"] = 2;
        self.cp_vitality_major = 0;
        self.cp_vitality_minor = 2;
        self.cp_vitality_bonus = 0;
        self setclientdvar( @"bo7_cp_vitality_pick_ack", "accepted:2" );
        setdvar( @"bo7_cp_augments_transport", "perk=vitality pick=2 major=0 minor=2 bonus=0" );
        return;
    }
    if ( value == 5010 || ( isstring( value ) && value == "5010" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["vitality"] = 10;
        self.cp_vitality_major = 1;
        self.cp_vitality_minor = 0;
        self.cp_vitality_bonus = 0;
        self setclientdvar( @"bo7_cp_vitality_pick_ack", "accepted:10" );
        setdvar( @"bo7_cp_augments_transport", "perk=vitality pick=10 major=1 minor=0 bonus=0" );
        return;
    }
    if ( value == 5011 || ( isstring( value ) && value == "5011" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["vitality"] = 11;
        self.cp_vitality_major = 1;
        self.cp_vitality_minor = 1;
        self.cp_vitality_bonus = 0;
        self setclientdvar( @"bo7_cp_vitality_pick_ack", "accepted:11" );
        setdvar( @"bo7_cp_augments_transport", "perk=vitality pick=11 major=1 minor=1 bonus=0" );
        return;
    }
    if ( value == 5012 || ( isstring( value ) && value == "5012" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["vitality"] = 12;
        self.cp_vitality_major = 1;
        self.cp_vitality_minor = 2;
        self.cp_vitality_bonus = 0;
        self setclientdvar( @"bo7_cp_vitality_pick_ack", "accepted:12" );
        setdvar( @"bo7_cp_augments_transport", "perk=vitality pick=12 major=1 minor=2 bonus=0" );
        return;
    }
    if ( value == 5020 || ( isstring( value ) && value == "5020" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["vitality"] = 20;
        self.cp_vitality_major = 2;
        self.cp_vitality_minor = 0;
        self.cp_vitality_bonus = 0;
        self setclientdvar( @"bo7_cp_vitality_pick_ack", "accepted:20" );
        setdvar( @"bo7_cp_augments_transport", "perk=vitality pick=20 major=2 minor=0 bonus=0" );
        return;
    }
    if ( value == 5021 || ( isstring( value ) && value == "5021" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["vitality"] = 21;
        self.cp_vitality_major = 2;
        self.cp_vitality_minor = 1;
        self.cp_vitality_bonus = 0;
        self setclientdvar( @"bo7_cp_vitality_pick_ack", "accepted:21" );
        setdvar( @"bo7_cp_augments_transport", "perk=vitality pick=21 major=2 minor=1 bonus=0" );
        return;
    }
    if ( value == 5022 || ( isstring( value ) && value == "5022" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["vitality"] = 22;
        self.cp_vitality_major = 2;
        self.cp_vitality_minor = 2;
        self.cp_vitality_bonus = 0;
        self setclientdvar( @"bo7_cp_vitality_pick_ack", "accepted:22" );
        setdvar( @"bo7_cp_augments_transport", "perk=vitality pick=22 major=2 minor=2 bonus=0" );
        return;
    }
    if ( value == 5100 || ( isstring( value ) && value == "5100" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["vitality"] = 100;
        self.cp_vitality_major = 0;
        self.cp_vitality_minor = 0;
        self.cp_vitality_bonus = 1;
        self setclientdvar( @"bo7_cp_vitality_pick_ack", "accepted:100" );
        setdvar( @"bo7_cp_augments_transport", "perk=vitality pick=100 major=0 minor=0 bonus=1" );
        return;
    }
    if ( value == 5102 || ( isstring( value ) && value == "5102" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["vitality"] = 102;
        self.cp_vitality_major = 0;
        self.cp_vitality_minor = 2;
        self.cp_vitality_bonus = 1;
        self setclientdvar( @"bo7_cp_vitality_pick_ack", "accepted:102" );
        setdvar( @"bo7_cp_augments_transport", "perk=vitality pick=102 major=0 minor=2 bonus=1" );
        return;
    }
    if ( value == 5110 || ( isstring( value ) && value == "5110" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["vitality"] = 110;
        self.cp_vitality_major = 1;
        self.cp_vitality_minor = 0;
        self.cp_vitality_bonus = 1;
        self setclientdvar( @"bo7_cp_vitality_pick_ack", "accepted:110" );
        setdvar( @"bo7_cp_augments_transport", "perk=vitality pick=110 major=1 minor=0 bonus=1" );
        return;
    }
    if ( value == 5112 || ( isstring( value ) && value == "5112" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["vitality"] = 112;
        self.cp_vitality_major = 1;
        self.cp_vitality_minor = 2;
        self.cp_vitality_bonus = 1;
        self setclientdvar( @"bo7_cp_vitality_pick_ack", "accepted:112" );
        setdvar( @"bo7_cp_augments_transport", "perk=vitality pick=112 major=1 minor=2 bonus=1" );
        return;
    }
    if ( value == 5120 || ( isstring( value ) && value == "5120" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["vitality"] = 120;
        self.cp_vitality_major = 2;
        self.cp_vitality_minor = 0;
        self.cp_vitality_bonus = 1;
        self setclientdvar( @"bo7_cp_vitality_pick_ack", "accepted:120" );
        setdvar( @"bo7_cp_augments_transport", "perk=vitality pick=120 major=2 minor=0 bonus=1" );
        return;
    }
    if ( value == 5122 || ( isstring( value ) && value == "5122" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["vitality"] = 122;
        self.cp_vitality_major = 2;
        self.cp_vitality_minor = 2;
        self.cp_vitality_bonus = 1;
        self setclientdvar( @"bo7_cp_vitality_pick_ack", "accepted:122" );
        setdvar( @"bo7_cp_augments_transport", "perk=vitality pick=122 major=2 minor=2 bonus=1" );
        return;
    }
    if ( value == 5200 || ( isstring( value ) && value == "5200" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["vitality"] = 200;
        self.cp_vitality_major = 0;
        self.cp_vitality_minor = 0;
        self.cp_vitality_bonus = 2;
        self setclientdvar( @"bo7_cp_vitality_pick_ack", "accepted:200" );
        setdvar( @"bo7_cp_augments_transport", "perk=vitality pick=200 major=0 minor=0 bonus=2" );
        return;
    }
    if ( value == 5201 || ( isstring( value ) && value == "5201" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["vitality"] = 201;
        self.cp_vitality_major = 0;
        self.cp_vitality_minor = 1;
        self.cp_vitality_bonus = 2;
        self setclientdvar( @"bo7_cp_vitality_pick_ack", "accepted:201" );
        setdvar( @"bo7_cp_augments_transport", "perk=vitality pick=201 major=0 minor=1 bonus=2" );
        return;
    }
    if ( value == 5210 || ( isstring( value ) && value == "5210" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["vitality"] = 210;
        self.cp_vitality_major = 1;
        self.cp_vitality_minor = 0;
        self.cp_vitality_bonus = 2;
        self setclientdvar( @"bo7_cp_vitality_pick_ack", "accepted:210" );
        setdvar( @"bo7_cp_augments_transport", "perk=vitality pick=210 major=1 minor=0 bonus=2" );
        return;
    }
    if ( value == 5211 || ( isstring( value ) && value == "5211" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["vitality"] = 211;
        self.cp_vitality_major = 1;
        self.cp_vitality_minor = 1;
        self.cp_vitality_bonus = 2;
        self setclientdvar( @"bo7_cp_vitality_pick_ack", "accepted:211" );
        setdvar( @"bo7_cp_augments_transport", "perk=vitality pick=211 major=1 minor=1 bonus=2" );
        return;
    }
    if ( value == 5220 || ( isstring( value ) && value == "5220" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["vitality"] = 220;
        self.cp_vitality_major = 2;
        self.cp_vitality_minor = 0;
        self.cp_vitality_bonus = 2;
        self setclientdvar( @"bo7_cp_vitality_pick_ack", "accepted:220" );
        setdvar( @"bo7_cp_augments_transport", "perk=vitality pick=220 major=2 minor=0 bonus=2" );
        return;
    }
    if ( value == 5221 || ( isstring( value ) && value == "5221" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["vitality"] = 221;
        self.cp_vitality_major = 2;
        self.cp_vitality_minor = 1;
        self.cp_vitality_bonus = 2;
        self setclientdvar( @"bo7_cp_vitality_pick_ack", "accepted:221" );
        setdvar( @"bo7_cp_augments_transport", "perk=vitality pick=221 major=2 minor=1 bonus=2" );
        return;
    }
}

function cp_receive_electric_cherry_pick( channel, value )
{
    if ( !isplayer( self ) || !isdefined( value ) || ( channel != "perk_choice_purchase" && channel != "custom_perk_choice_purchase" ) )
    {
        return;
    }
    if ( value == 6000 || ( isstring( value ) && value == "6000" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 0;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 0;
        self.cp_electric_cherry_bonus = 0;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:0" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=0 major=0 minor=0 bonus=0" );
        return;
    }
    if ( value == 6001 || ( isstring( value ) && value == "6001" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 1;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 1;
        self.cp_electric_cherry_bonus = 0;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:1" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=1 major=0 minor=1 bonus=0" );
        return;
    }
    if ( value == 6002 || ( isstring( value ) && value == "6002" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 2;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 2;
        self.cp_electric_cherry_bonus = 0;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:2" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=2 major=0 minor=2 bonus=0" );
        return;
    }
    if ( value == 6003 || ( isstring( value ) && value == "6003" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 3;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 3;
        self.cp_electric_cherry_bonus = 0;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:3" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=3 major=0 minor=3 bonus=0" );
        return;
    }
    if ( value == 6010 || ( isstring( value ) && value == "6010" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 10;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 0;
        self.cp_electric_cherry_bonus = 0;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:10" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=10 major=1 minor=0 bonus=0" );
        return;
    }
    if ( value == 6011 || ( isstring( value ) && value == "6011" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 11;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 1;
        self.cp_electric_cherry_bonus = 0;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:11" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=11 major=1 minor=1 bonus=0" );
        return;
    }
    if ( value == 6012 || ( isstring( value ) && value == "6012" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 12;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 2;
        self.cp_electric_cherry_bonus = 0;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:12" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=12 major=1 minor=2 bonus=0" );
        return;
    }
    if ( value == 6013 || ( isstring( value ) && value == "6013" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 13;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 3;
        self.cp_electric_cherry_bonus = 0;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:13" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=13 major=1 minor=3 bonus=0" );
        return;
    }
    if ( value == 6020 || ( isstring( value ) && value == "6020" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 20;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 0;
        self.cp_electric_cherry_bonus = 0;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:20" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=20 major=2 minor=0 bonus=0" );
        return;
    }
    if ( value == 6021 || ( isstring( value ) && value == "6021" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 21;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 1;
        self.cp_electric_cherry_bonus = 0;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:21" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=21 major=2 minor=1 bonus=0" );
        return;
    }
    if ( value == 6022 || ( isstring( value ) && value == "6022" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 22;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 2;
        self.cp_electric_cherry_bonus = 0;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:22" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=22 major=2 minor=2 bonus=0" );
        return;
    }
    if ( value == 6023 || ( isstring( value ) && value == "6023" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 23;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 3;
        self.cp_electric_cherry_bonus = 0;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:23" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=23 major=2 minor=3 bonus=0" );
        return;
    }
    if ( value == 6100 || ( isstring( value ) && value == "6100" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 100;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 0;
        self.cp_electric_cherry_bonus = 1;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:100" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=100 major=0 minor=0 bonus=1" );
        return;
    }
    if ( value == 6102 || ( isstring( value ) && value == "6102" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 102;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 2;
        self.cp_electric_cherry_bonus = 1;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:102" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=102 major=0 minor=2 bonus=1" );
        return;
    }
    if ( value == 6103 || ( isstring( value ) && value == "6103" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 103;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 3;
        self.cp_electric_cherry_bonus = 1;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:103" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=103 major=0 minor=3 bonus=1" );
        return;
    }
    if ( value == 6110 || ( isstring( value ) && value == "6110" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 110;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 0;
        self.cp_electric_cherry_bonus = 1;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:110" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=110 major=1 minor=0 bonus=1" );
        return;
    }
    if ( value == 6112 || ( isstring( value ) && value == "6112" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 112;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 2;
        self.cp_electric_cherry_bonus = 1;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:112" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=112 major=1 minor=2 bonus=1" );
        return;
    }
    if ( value == 6113 || ( isstring( value ) && value == "6113" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 113;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 3;
        self.cp_electric_cherry_bonus = 1;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:113" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=113 major=1 minor=3 bonus=1" );
        return;
    }
    if ( value == 6120 || ( isstring( value ) && value == "6120" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 120;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 0;
        self.cp_electric_cherry_bonus = 1;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:120" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=120 major=2 minor=0 bonus=1" );
        return;
    }
    if ( value == 6122 || ( isstring( value ) && value == "6122" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 122;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 2;
        self.cp_electric_cherry_bonus = 1;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:122" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=122 major=2 minor=2 bonus=1" );
        return;
    }
    if ( value == 6123 || ( isstring( value ) && value == "6123" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 123;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 3;
        self.cp_electric_cherry_bonus = 1;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:123" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=123 major=2 minor=3 bonus=1" );
        return;
    }
    if ( value == 6200 || ( isstring( value ) && value == "6200" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 200;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 0;
        self.cp_electric_cherry_bonus = 2;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:200" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=200 major=0 minor=0 bonus=2" );
        return;
    }
    if ( value == 6201 || ( isstring( value ) && value == "6201" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 201;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 1;
        self.cp_electric_cherry_bonus = 2;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:201" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=201 major=0 minor=1 bonus=2" );
        return;
    }
    if ( value == 6203 || ( isstring( value ) && value == "6203" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 203;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 3;
        self.cp_electric_cherry_bonus = 2;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:203" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=203 major=0 minor=3 bonus=2" );
        return;
    }
    if ( value == 6210 || ( isstring( value ) && value == "6210" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 210;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 0;
        self.cp_electric_cherry_bonus = 2;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:210" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=210 major=1 minor=0 bonus=2" );
        return;
    }
    if ( value == 6211 || ( isstring( value ) && value == "6211" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 211;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 1;
        self.cp_electric_cherry_bonus = 2;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:211" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=211 major=1 minor=1 bonus=2" );
        return;
    }
    if ( value == 6213 || ( isstring( value ) && value == "6213" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 213;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 3;
        self.cp_electric_cherry_bonus = 2;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:213" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=213 major=1 minor=3 bonus=2" );
        return;
    }
    if ( value == 6220 || ( isstring( value ) && value == "6220" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 220;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 0;
        self.cp_electric_cherry_bonus = 2;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:220" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=220 major=2 minor=0 bonus=2" );
        return;
    }
    if ( value == 6221 || ( isstring( value ) && value == "6221" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 221;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 1;
        self.cp_electric_cherry_bonus = 2;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:221" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=221 major=2 minor=1 bonus=2" );
        return;
    }
    if ( value == 6223 || ( isstring( value ) && value == "6223" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 223;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 3;
        self.cp_electric_cherry_bonus = 2;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:223" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=223 major=2 minor=3 bonus=2" );
        return;
    }
    if ( value == 6300 || ( isstring( value ) && value == "6300" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 300;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 0;
        self.cp_electric_cherry_bonus = 3;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:300" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=300 major=0 minor=0 bonus=3" );
        return;
    }
    if ( value == 6301 || ( isstring( value ) && value == "6301" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 301;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 1;
        self.cp_electric_cherry_bonus = 3;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:301" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=301 major=0 minor=1 bonus=3" );
        return;
    }
    if ( value == 6302 || ( isstring( value ) && value == "6302" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 302;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 2;
        self.cp_electric_cherry_bonus = 3;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:302" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=302 major=0 minor=2 bonus=3" );
        return;
    }
    if ( value == 6310 || ( isstring( value ) && value == "6310" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 310;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 0;
        self.cp_electric_cherry_bonus = 3;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:310" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=310 major=1 minor=0 bonus=3" );
        return;
    }
    if ( value == 6311 || ( isstring( value ) && value == "6311" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 311;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 1;
        self.cp_electric_cherry_bonus = 3;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:311" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=311 major=1 minor=1 bonus=3" );
        return;
    }
    if ( value == 6312 || ( isstring( value ) && value == "6312" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 312;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 2;
        self.cp_electric_cherry_bonus = 3;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:312" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=312 major=1 minor=2 bonus=3" );
        return;
    }
    if ( value == 6320 || ( isstring( value ) && value == "6320" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 320;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 0;
        self.cp_electric_cherry_bonus = 3;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:320" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=320 major=2 minor=0 bonus=3" );
        return;
    }
    if ( value == 6321 || ( isstring( value ) && value == "6321" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 321;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 1;
        self.cp_electric_cherry_bonus = 3;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:321" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=321 major=2 minor=1 bonus=3" );
        return;
    }
    if ( value == 6322 || ( isstring( value ) && value == "6322" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["electric_cherry"] = 322;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 2;
        self.cp_electric_cherry_bonus = 3;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:322" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=322 major=2 minor=2 bonus=3" );
        return;
    }
}

function cp_receive_tortoise_pick( channel, value )
{
    if ( !isplayer( self ) || !isdefined( value ) || ( channel != "perk_choice_purchase" && channel != "custom_perk_choice_purchase" ) )
    {
        return;
    }
    if ( value == 7000 || ( isstring( value ) && value == "7000" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["tortoise"] = 0;
        self.cp_tortoise_major = 0;
        self.cp_tortoise_minor = 0;
        self.cp_tortoise_bonus = 0;
        self setclientdvar( @"bo7_cp_tortoise_pick_ack", "accepted:0" );
        setdvar( @"bo7_cp_augments_transport", "perk=tortoise pick=0 major=0 minor=0 bonus=0" );
        return;
    }
    if ( value == 7001 || ( isstring( value ) && value == "7001" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["tortoise"] = 1;
        self.cp_tortoise_major = 0;
        self.cp_tortoise_minor = 1;
        self.cp_tortoise_bonus = 0;
        self setclientdvar( @"bo7_cp_tortoise_pick_ack", "accepted:1" );
        setdvar( @"bo7_cp_augments_transport", "perk=tortoise pick=1 major=0 minor=1 bonus=0" );
        return;
    }
    if ( value == 7010 || ( isstring( value ) && value == "7010" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["tortoise"] = 10;
        self.cp_tortoise_major = 1;
        self.cp_tortoise_minor = 0;
        self.cp_tortoise_bonus = 0;
        self setclientdvar( @"bo7_cp_tortoise_pick_ack", "accepted:10" );
        setdvar( @"bo7_cp_augments_transport", "perk=tortoise pick=10 major=1 minor=0 bonus=0" );
        return;
    }
    if ( value == 7011 || ( isstring( value ) && value == "7011" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["tortoise"] = 11;
        self.cp_tortoise_major = 1;
        self.cp_tortoise_minor = 1;
        self.cp_tortoise_bonus = 0;
        self setclientdvar( @"bo7_cp_tortoise_pick_ack", "accepted:11" );
        setdvar( @"bo7_cp_augments_transport", "perk=tortoise pick=11 major=1 minor=1 bonus=0" );
        return;
    }
    if ( value == 7020 || ( isstring( value ) && value == "7020" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["tortoise"] = 20;
        self.cp_tortoise_major = 2;
        self.cp_tortoise_minor = 0;
        self.cp_tortoise_bonus = 0;
        self setclientdvar( @"bo7_cp_tortoise_pick_ack", "accepted:20" );
        setdvar( @"bo7_cp_augments_transport", "perk=tortoise pick=20 major=2 minor=0 bonus=0" );
        return;
    }
    if ( value == 7021 || ( isstring( value ) && value == "7021" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["tortoise"] = 21;
        self.cp_tortoise_major = 2;
        self.cp_tortoise_minor = 1;
        self.cp_tortoise_bonus = 0;
        self setclientdvar( @"bo7_cp_tortoise_pick_ack", "accepted:21" );
        setdvar( @"bo7_cp_augments_transport", "perk=tortoise pick=21 major=2 minor=1 bonus=0" );
        return;
    }
    if ( value == 7100 || ( isstring( value ) && value == "7100" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["tortoise"] = 100;
        self.cp_tortoise_major = 0;
        self.cp_tortoise_minor = 0;
        self.cp_tortoise_bonus = 1;
        self setclientdvar( @"bo7_cp_tortoise_pick_ack", "accepted:100" );
        setdvar( @"bo7_cp_augments_transport", "perk=tortoise pick=100 major=0 minor=0 bonus=1" );
        return;
    }
    if ( value == 7110 || ( isstring( value ) && value == "7110" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["tortoise"] = 110;
        self.cp_tortoise_major = 1;
        self.cp_tortoise_minor = 0;
        self.cp_tortoise_bonus = 1;
        self setclientdvar( @"bo7_cp_tortoise_pick_ack", "accepted:110" );
        setdvar( @"bo7_cp_augments_transport", "perk=tortoise pick=110 major=1 minor=0 bonus=1" );
        return;
    }
    if ( value == 7120 || ( isstring( value ) && value == "7120" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["tortoise"] = 120;
        self.cp_tortoise_major = 2;
        self.cp_tortoise_minor = 0;
        self.cp_tortoise_bonus = 1;
        self setclientdvar( @"bo7_cp_tortoise_pick_ack", "accepted:120" );
        setdvar( @"bo7_cp_augments_transport", "perk=tortoise pick=120 major=2 minor=0 bonus=1" );
        return;
    }
}

function cp_receive_bandolier_pick( channel, value )
{
    if ( !isplayer( self ) || !isdefined( value ) || ( channel != "perk_choice_purchase" && channel != "custom_perk_choice_purchase" ) )
    {
        return;
    }
    if ( value == 8000 || ( isstring( value ) && value == "8000" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["bandolier"] = 0;
        self.cp_bandolier_major = 0;
        self.cp_bandolier_minor = 0;
        self.cp_bandolier_bonus = 0;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:0" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=0 major=0 minor=0 bonus=0" );
        return;
    }
    if ( value == 8001 || ( isstring( value ) && value == "8001" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["bandolier"] = 1;
        self.cp_bandolier_major = 0;
        self.cp_bandolier_minor = 1;
        self.cp_bandolier_bonus = 0;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:1" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=1 major=0 minor=1 bonus=0" );
        return;
    }
    if ( value == 8002 || ( isstring( value ) && value == "8002" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["bandolier"] = 2;
        self.cp_bandolier_major = 0;
        self.cp_bandolier_minor = 2;
        self.cp_bandolier_bonus = 0;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:2" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=2 major=0 minor=2 bonus=0" );
        return;
    }
    if ( value == 8010 || ( isstring( value ) && value == "8010" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["bandolier"] = 10;
        self.cp_bandolier_major = 1;
        self.cp_bandolier_minor = 0;
        self.cp_bandolier_bonus = 0;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:10" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=10 major=1 minor=0 bonus=0" );
        return;
    }
    if ( value == 8011 || ( isstring( value ) && value == "8011" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["bandolier"] = 11;
        self.cp_bandolier_major = 1;
        self.cp_bandolier_minor = 1;
        self.cp_bandolier_bonus = 0;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:11" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=11 major=1 minor=1 bonus=0" );
        return;
    }
    if ( value == 8012 || ( isstring( value ) && value == "8012" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["bandolier"] = 12;
        self.cp_bandolier_major = 1;
        self.cp_bandolier_minor = 2;
        self.cp_bandolier_bonus = 0;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:12" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=12 major=1 minor=2 bonus=0" );
        return;
    }
    if ( value == 8020 || ( isstring( value ) && value == "8020" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["bandolier"] = 20;
        self.cp_bandolier_major = 2;
        self.cp_bandolier_minor = 0;
        self.cp_bandolier_bonus = 0;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:20" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=20 major=2 minor=0 bonus=0" );
        return;
    }
    if ( value == 8021 || ( isstring( value ) && value == "8021" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["bandolier"] = 21;
        self.cp_bandolier_major = 2;
        self.cp_bandolier_minor = 1;
        self.cp_bandolier_bonus = 0;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:21" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=21 major=2 minor=1 bonus=0" );
        return;
    }
    if ( value == 8022 || ( isstring( value ) && value == "8022" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["bandolier"] = 22;
        self.cp_bandolier_major = 2;
        self.cp_bandolier_minor = 2;
        self.cp_bandolier_bonus = 0;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:22" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=22 major=2 minor=2 bonus=0" );
        return;
    }
    if ( value == 8100 || ( isstring( value ) && value == "8100" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["bandolier"] = 100;
        self.cp_bandolier_major = 0;
        self.cp_bandolier_minor = 0;
        self.cp_bandolier_bonus = 1;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:100" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=100 major=0 minor=0 bonus=1" );
        return;
    }
    if ( value == 8102 || ( isstring( value ) && value == "8102" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["bandolier"] = 102;
        self.cp_bandolier_major = 0;
        self.cp_bandolier_minor = 2;
        self.cp_bandolier_bonus = 1;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:102" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=102 major=0 minor=2 bonus=1" );
        return;
    }
    if ( value == 8110 || ( isstring( value ) && value == "8110" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["bandolier"] = 110;
        self.cp_bandolier_major = 1;
        self.cp_bandolier_minor = 0;
        self.cp_bandolier_bonus = 1;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:110" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=110 major=1 minor=0 bonus=1" );
        return;
    }
    if ( value == 8112 || ( isstring( value ) && value == "8112" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["bandolier"] = 112;
        self.cp_bandolier_major = 1;
        self.cp_bandolier_minor = 2;
        self.cp_bandolier_bonus = 1;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:112" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=112 major=1 minor=2 bonus=1" );
        return;
    }
    if ( value == 8120 || ( isstring( value ) && value == "8120" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["bandolier"] = 120;
        self.cp_bandolier_major = 2;
        self.cp_bandolier_minor = 0;
        self.cp_bandolier_bonus = 1;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:120" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=120 major=2 minor=0 bonus=1" );
        return;
    }
    if ( value == 8122 || ( isstring( value ) && value == "8122" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["bandolier"] = 122;
        self.cp_bandolier_major = 2;
        self.cp_bandolier_minor = 2;
        self.cp_bandolier_bonus = 1;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:122" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=122 major=2 minor=2 bonus=1" );
        return;
    }
    if ( value == 8200 || ( isstring( value ) && value == "8200" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["bandolier"] = 200;
        self.cp_bandolier_major = 0;
        self.cp_bandolier_minor = 0;
        self.cp_bandolier_bonus = 2;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:200" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=200 major=0 minor=0 bonus=2" );
        return;
    }
    if ( value == 8201 || ( isstring( value ) && value == "8201" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["bandolier"] = 201;
        self.cp_bandolier_major = 0;
        self.cp_bandolier_minor = 1;
        self.cp_bandolier_bonus = 2;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:201" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=201 major=0 minor=1 bonus=2" );
        return;
    }
    if ( value == 8210 || ( isstring( value ) && value == "8210" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["bandolier"] = 210;
        self.cp_bandolier_major = 1;
        self.cp_bandolier_minor = 0;
        self.cp_bandolier_bonus = 2;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:210" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=210 major=1 minor=0 bonus=2" );
        return;
    }
    if ( value == 8211 || ( isstring( value ) && value == "8211" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["bandolier"] = 211;
        self.cp_bandolier_major = 1;
        self.cp_bandolier_minor = 1;
        self.cp_bandolier_bonus = 2;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:211" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=211 major=1 minor=1 bonus=2" );
        return;
    }
    if ( value == 8220 || ( isstring( value ) && value == "8220" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["bandolier"] = 220;
        self.cp_bandolier_major = 2;
        self.cp_bandolier_minor = 0;
        self.cp_bandolier_bonus = 2;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:220" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=220 major=2 minor=0 bonus=2" );
        return;
    }
    if ( value == 8221 || ( isstring( value ) && value == "8221" ) )
    {
        if ( !isdefined( self.cp_picks ) )
        {
            self.cp_picks = [];
        }
        self.cp_picks["bandolier"] = 221;
        self.cp_bandolier_major = 2;
        self.cp_bandolier_minor = 1;
        self.cp_bandolier_bonus = 2;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:221" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=221 major=2 minor=1 bonus=2" );
        return;
    }
}

function cp_hud_snapshot_watch()
{
    level endon( #"game_ended" );
    level utility::flag_wait_all( "StartGameTypeCallbackFinished", "zombie_perks_init_complete" );
    setdvar( @"bo7_cp_hud_watch_debug", "running" );
    while ( true )
    {
        foreach ( player in level.players )
        {
            if ( isdefined( player ) && isplayer( player ) )
            {
                player cp_publish_slot_perks();
            }
        }
        wait 0.5;
    }
}

function cp_publish_slot_perks()
{
    if ( !isdefined( self.cp_hud_slot ) )
    {
        return;
    }
    hud_slot = self.cp_hud_slot;
    if ( hud_slot < 0 || hud_slot > 3 )
    {
        setdvar( @"bo7_cp_hud_watch_debug", "rejected slot=" + hud_slot );
        return;
    }
    refs = [];
    if ( isdefined( self.perks_active ) )
    {
        foreach ( ref in self.perks_active )
        {
            if ( isdefined( ref ) && ref != "specialty_choice" && !arraycontains( refs, ref ) )
            {
                refs[ refs.size ] = ref;
            }
        }
    }
    if ( isdefined( self.a_perks ) )
    {
        foreach ( ref, active in self.a_perks )
        {
            if ( isdefined( active ) && ref != "specialty_choice" && !arraycontains( refs, ref ) )
            {
                refs[ refs.size ] = ref;
            }
        }
    }
    snapshot = "slot=" + hud_slot + ";v1:";
    delimiter = "";
    foreach ( ref in refs )
    {
        snapshot = snapshot + delimiter + ref;
        delimiter = ",";
    }
    snapshot = snapshot + ";eternal:";
    delimiter = "";
    if (isdefined(self.perma_perks))
    {
        foreach (ref in refs)
        {
            permanent = arraycontains(self.perma_perks, ref);
            if (!permanent && isstring(ref)) permanent = arraycontains(self.perma_perks, getxhash(ref));
            if (permanent)
            {
                snapshot = snapshot + delimiter + ref;
                delimiter = ",";
            }
        }
    }
    if ( isdefined( self.cp_hud_watch_snapshot ) && self.cp_hud_watch_snapshot == snapshot )
    {
        return;
    }
    self.cp_hud_watch_snapshot = snapshot;
    if ( hud_slot == 0 )
    {
        setdvar( @"bo7_cp_hud_slot_0", snapshot );
        self setclientdvar( @"bo7_cp_hud_slot_0", snapshot );
    }
    if ( hud_slot == 1 )
    {
        setdvar( @"bo7_cp_hud_slot_1", snapshot );
        self setclientdvar( @"bo7_cp_hud_slot_1", snapshot );
    }
    if ( hud_slot == 2 )
    {
        setdvar( @"bo7_cp_hud_slot_2", snapshot );
        self setclientdvar( @"bo7_cp_hud_slot_2", snapshot );
    }
    if ( hud_slot == 3 )
    {
        setdvar( @"bo7_cp_hud_slot_3", snapshot );
        self setclientdvar( @"bo7_cp_hud_slot_3", snapshot );
    }
    setdvar( @"bo7_cp_hud_watch_debug", "published slot=" + hud_slot + " count=" + refs.size );
}

// BEGIN GENERATED COOP electric_cherry
// @coop_sync electric_cherry 6000
function cp_receive_generated_electric_cherry( channel, value )
{
    if ( !isplayer( self ) || !isdefined( value ) || ( channel != "perk_choice_purchase" && channel != "custom_perk_choice_purchase" ) ) return false;
    if ( value == 6000 || ( isstring( value ) && value == "6000" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 0;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 0;
        self.cp_electric_cherry_bonus = 0;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:0" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=0 major=0 minor=0 bonus=0" );
        return true;
    }
    if ( value == 6001 || ( isstring( value ) && value == "6001" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 1;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 1;
        self.cp_electric_cherry_bonus = 0;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:1" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=1 major=0 minor=1 bonus=0" );
        return true;
    }
    if ( value == 6002 || ( isstring( value ) && value == "6002" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 2;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 2;
        self.cp_electric_cherry_bonus = 0;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:2" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=2 major=0 minor=2 bonus=0" );
        return true;
    }
    if ( value == 6003 || ( isstring( value ) && value == "6003" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 3;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 3;
        self.cp_electric_cherry_bonus = 0;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:3" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=3 major=0 minor=3 bonus=0" );
        return true;
    }
    if ( value == 6010 || ( isstring( value ) && value == "6010" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 10;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 0;
        self.cp_electric_cherry_bonus = 0;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:10" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=10 major=1 minor=0 bonus=0" );
        return true;
    }
    if ( value == 6011 || ( isstring( value ) && value == "6011" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 11;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 1;
        self.cp_electric_cherry_bonus = 0;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:11" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=11 major=1 minor=1 bonus=0" );
        return true;
    }
    if ( value == 6012 || ( isstring( value ) && value == "6012" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 12;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 2;
        self.cp_electric_cherry_bonus = 0;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:12" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=12 major=1 minor=2 bonus=0" );
        return true;
    }
    if ( value == 6013 || ( isstring( value ) && value == "6013" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 13;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 3;
        self.cp_electric_cherry_bonus = 0;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:13" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=13 major=1 minor=3 bonus=0" );
        return true;
    }
    if ( value == 6020 || ( isstring( value ) && value == "6020" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 20;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 0;
        self.cp_electric_cherry_bonus = 0;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:20" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=20 major=2 minor=0 bonus=0" );
        return true;
    }
    if ( value == 6021 || ( isstring( value ) && value == "6021" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 21;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 1;
        self.cp_electric_cherry_bonus = 0;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:21" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=21 major=2 minor=1 bonus=0" );
        return true;
    }
    if ( value == 6022 || ( isstring( value ) && value == "6022" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 22;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 2;
        self.cp_electric_cherry_bonus = 0;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:22" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=22 major=2 minor=2 bonus=0" );
        return true;
    }
    if ( value == 6023 || ( isstring( value ) && value == "6023" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 23;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 3;
        self.cp_electric_cherry_bonus = 0;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:23" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=23 major=2 minor=3 bonus=0" );
        return true;
    }
    if ( value == 6100 || ( isstring( value ) && value == "6100" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 100;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 0;
        self.cp_electric_cherry_bonus = 1;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:100" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=100 major=0 minor=0 bonus=1" );
        return true;
    }
    if ( value == 6102 || ( isstring( value ) && value == "6102" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 102;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 2;
        self.cp_electric_cherry_bonus = 1;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:102" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=102 major=0 minor=2 bonus=1" );
        return true;
    }
    if ( value == 6103 || ( isstring( value ) && value == "6103" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 103;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 3;
        self.cp_electric_cherry_bonus = 1;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:103" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=103 major=0 minor=3 bonus=1" );
        return true;
    }
    if ( value == 6110 || ( isstring( value ) && value == "6110" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 110;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 0;
        self.cp_electric_cherry_bonus = 1;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:110" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=110 major=1 minor=0 bonus=1" );
        return true;
    }
    if ( value == 6112 || ( isstring( value ) && value == "6112" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 112;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 2;
        self.cp_electric_cherry_bonus = 1;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:112" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=112 major=1 minor=2 bonus=1" );
        return true;
    }
    if ( value == 6113 || ( isstring( value ) && value == "6113" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 113;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 3;
        self.cp_electric_cherry_bonus = 1;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:113" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=113 major=1 minor=3 bonus=1" );
        return true;
    }
    if ( value == 6120 || ( isstring( value ) && value == "6120" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 120;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 0;
        self.cp_electric_cherry_bonus = 1;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:120" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=120 major=2 minor=0 bonus=1" );
        return true;
    }
    if ( value == 6122 || ( isstring( value ) && value == "6122" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 122;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 2;
        self.cp_electric_cherry_bonus = 1;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:122" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=122 major=2 minor=2 bonus=1" );
        return true;
    }
    if ( value == 6123 || ( isstring( value ) && value == "6123" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 123;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 3;
        self.cp_electric_cherry_bonus = 1;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:123" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=123 major=2 minor=3 bonus=1" );
        return true;
    }
    if ( value == 6200 || ( isstring( value ) && value == "6200" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 200;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 0;
        self.cp_electric_cherry_bonus = 2;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:200" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=200 major=0 minor=0 bonus=2" );
        return true;
    }
    if ( value == 6201 || ( isstring( value ) && value == "6201" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 201;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 1;
        self.cp_electric_cherry_bonus = 2;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:201" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=201 major=0 minor=1 bonus=2" );
        return true;
    }
    if ( value == 6203 || ( isstring( value ) && value == "6203" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 203;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 3;
        self.cp_electric_cherry_bonus = 2;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:203" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=203 major=0 minor=3 bonus=2" );
        return true;
    }
    if ( value == 6210 || ( isstring( value ) && value == "6210" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 210;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 0;
        self.cp_electric_cherry_bonus = 2;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:210" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=210 major=1 minor=0 bonus=2" );
        return true;
    }
    if ( value == 6211 || ( isstring( value ) && value == "6211" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 211;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 1;
        self.cp_electric_cherry_bonus = 2;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:211" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=211 major=1 minor=1 bonus=2" );
        return true;
    }
    if ( value == 6213 || ( isstring( value ) && value == "6213" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 213;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 3;
        self.cp_electric_cherry_bonus = 2;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:213" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=213 major=1 minor=3 bonus=2" );
        return true;
    }
    if ( value == 6220 || ( isstring( value ) && value == "6220" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 220;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 0;
        self.cp_electric_cherry_bonus = 2;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:220" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=220 major=2 minor=0 bonus=2" );
        return true;
    }
    if ( value == 6221 || ( isstring( value ) && value == "6221" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 221;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 1;
        self.cp_electric_cherry_bonus = 2;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:221" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=221 major=2 minor=1 bonus=2" );
        return true;
    }
    if ( value == 6223 || ( isstring( value ) && value == "6223" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 223;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 3;
        self.cp_electric_cherry_bonus = 2;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:223" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=223 major=2 minor=3 bonus=2" );
        return true;
    }
    if ( value == 6300 || ( isstring( value ) && value == "6300" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 300;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 0;
        self.cp_electric_cherry_bonus = 3;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:300" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=300 major=0 minor=0 bonus=3" );
        return true;
    }
    if ( value == 6301 || ( isstring( value ) && value == "6301" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 301;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 1;
        self.cp_electric_cherry_bonus = 3;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:301" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=301 major=0 minor=1 bonus=3" );
        return true;
    }
    if ( value == 6302 || ( isstring( value ) && value == "6302" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 302;
        self.cp_electric_cherry_major = 0;
        self.cp_electric_cherry_minor = 2;
        self.cp_electric_cherry_bonus = 3;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:302" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=302 major=0 minor=2 bonus=3" );
        return true;
    }
    if ( value == 6310 || ( isstring( value ) && value == "6310" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 310;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 0;
        self.cp_electric_cherry_bonus = 3;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:310" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=310 major=1 minor=0 bonus=3" );
        return true;
    }
    if ( value == 6311 || ( isstring( value ) && value == "6311" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 311;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 1;
        self.cp_electric_cherry_bonus = 3;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:311" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=311 major=1 minor=1 bonus=3" );
        return true;
    }
    if ( value == 6312 || ( isstring( value ) && value == "6312" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 312;
        self.cp_electric_cherry_major = 1;
        self.cp_electric_cherry_minor = 2;
        self.cp_electric_cherry_bonus = 3;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:312" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=312 major=1 minor=2 bonus=3" );
        return true;
    }
    if ( value == 6320 || ( isstring( value ) && value == "6320" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 320;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 0;
        self.cp_electric_cherry_bonus = 3;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:320" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=320 major=2 minor=0 bonus=3" );
        return true;
    }
    if ( value == 6321 || ( isstring( value ) && value == "6321" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 321;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 1;
        self.cp_electric_cherry_bonus = 3;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:321" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=321 major=2 minor=1 bonus=3" );
        return true;
    }
    if ( value == 6322 || ( isstring( value ) && value == "6322" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["electric_cherry"] = 322;
        self.cp_electric_cherry_major = 2;
        self.cp_electric_cherry_minor = 2;
        self.cp_electric_cherry_bonus = 3;
        self setclientdvar( @"bo7_cp_electric_cherry_pick_ack", "accepted:322" );
        setdvar( @"bo7_cp_augments_transport", "perk=electric_cherry pick=322 major=2 minor=2 bonus=3" );
        return true;
    }
    return false;
}
// END GENERATED COOP electric_cherry

// BEGIN GENERATED COOP bandolier
// @coop_sync bandolier 8000
function cp_receive_generated_bandolier( channel, value )
{
    if ( !isplayer( self ) || !isdefined( value ) || ( channel != "perk_choice_purchase" && channel != "custom_perk_choice_purchase" ) ) return false;
    if ( value == 8000 || ( isstring( value ) && value == "8000" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["bandolier"] = 0;
        self.cp_bandolier_major = 0;
        self.cp_bandolier_minor = 0;
        self.cp_bandolier_bonus = 0;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:0" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=0 major=0 minor=0 bonus=0" );
        return true;
    }
    if ( value == 8001 || ( isstring( value ) && value == "8001" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["bandolier"] = 1;
        self.cp_bandolier_major = 0;
        self.cp_bandolier_minor = 1;
        self.cp_bandolier_bonus = 0;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:1" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=1 major=0 minor=1 bonus=0" );
        return true;
    }
    if ( value == 8002 || ( isstring( value ) && value == "8002" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["bandolier"] = 2;
        self.cp_bandolier_major = 0;
        self.cp_bandolier_minor = 2;
        self.cp_bandolier_bonus = 0;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:2" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=2 major=0 minor=2 bonus=0" );
        return true;
    }
    if ( value == 8010 || ( isstring( value ) && value == "8010" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["bandolier"] = 10;
        self.cp_bandolier_major = 1;
        self.cp_bandolier_minor = 0;
        self.cp_bandolier_bonus = 0;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:10" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=10 major=1 minor=0 bonus=0" );
        return true;
    }
    if ( value == 8011 || ( isstring( value ) && value == "8011" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["bandolier"] = 11;
        self.cp_bandolier_major = 1;
        self.cp_bandolier_minor = 1;
        self.cp_bandolier_bonus = 0;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:11" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=11 major=1 minor=1 bonus=0" );
        return true;
    }
    if ( value == 8012 || ( isstring( value ) && value == "8012" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["bandolier"] = 12;
        self.cp_bandolier_major = 1;
        self.cp_bandolier_minor = 2;
        self.cp_bandolier_bonus = 0;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:12" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=12 major=1 minor=2 bonus=0" );
        return true;
    }
    if ( value == 8020 || ( isstring( value ) && value == "8020" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["bandolier"] = 20;
        self.cp_bandolier_major = 2;
        self.cp_bandolier_minor = 0;
        self.cp_bandolier_bonus = 0;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:20" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=20 major=2 minor=0 bonus=0" );
        return true;
    }
    if ( value == 8021 || ( isstring( value ) && value == "8021" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["bandolier"] = 21;
        self.cp_bandolier_major = 2;
        self.cp_bandolier_minor = 1;
        self.cp_bandolier_bonus = 0;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:21" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=21 major=2 minor=1 bonus=0" );
        return true;
    }
    if ( value == 8022 || ( isstring( value ) && value == "8022" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["bandolier"] = 22;
        self.cp_bandolier_major = 2;
        self.cp_bandolier_minor = 2;
        self.cp_bandolier_bonus = 0;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:22" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=22 major=2 minor=2 bonus=0" );
        return true;
    }
    if ( value == 8100 || ( isstring( value ) && value == "8100" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["bandolier"] = 100;
        self.cp_bandolier_major = 0;
        self.cp_bandolier_minor = 0;
        self.cp_bandolier_bonus = 1;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:100" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=100 major=0 minor=0 bonus=1" );
        return true;
    }
    if ( value == 8102 || ( isstring( value ) && value == "8102" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["bandolier"] = 102;
        self.cp_bandolier_major = 0;
        self.cp_bandolier_minor = 2;
        self.cp_bandolier_bonus = 1;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:102" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=102 major=0 minor=2 bonus=1" );
        return true;
    }
    if ( value == 8110 || ( isstring( value ) && value == "8110" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["bandolier"] = 110;
        self.cp_bandolier_major = 1;
        self.cp_bandolier_minor = 0;
        self.cp_bandolier_bonus = 1;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:110" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=110 major=1 minor=0 bonus=1" );
        return true;
    }
    if ( value == 8112 || ( isstring( value ) && value == "8112" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["bandolier"] = 112;
        self.cp_bandolier_major = 1;
        self.cp_bandolier_minor = 2;
        self.cp_bandolier_bonus = 1;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:112" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=112 major=1 minor=2 bonus=1" );
        return true;
    }
    if ( value == 8120 || ( isstring( value ) && value == "8120" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["bandolier"] = 120;
        self.cp_bandolier_major = 2;
        self.cp_bandolier_minor = 0;
        self.cp_bandolier_bonus = 1;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:120" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=120 major=2 minor=0 bonus=1" );
        return true;
    }
    if ( value == 8122 || ( isstring( value ) && value == "8122" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["bandolier"] = 122;
        self.cp_bandolier_major = 2;
        self.cp_bandolier_minor = 2;
        self.cp_bandolier_bonus = 1;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:122" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=122 major=2 minor=2 bonus=1" );
        return true;
    }
    if ( value == 8200 || ( isstring( value ) && value == "8200" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["bandolier"] = 200;
        self.cp_bandolier_major = 0;
        self.cp_bandolier_minor = 0;
        self.cp_bandolier_bonus = 2;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:200" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=200 major=0 minor=0 bonus=2" );
        return true;
    }
    if ( value == 8201 || ( isstring( value ) && value == "8201" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["bandolier"] = 201;
        self.cp_bandolier_major = 0;
        self.cp_bandolier_minor = 1;
        self.cp_bandolier_bonus = 2;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:201" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=201 major=0 minor=1 bonus=2" );
        return true;
    }
    if ( value == 8210 || ( isstring( value ) && value == "8210" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["bandolier"] = 210;
        self.cp_bandolier_major = 1;
        self.cp_bandolier_minor = 0;
        self.cp_bandolier_bonus = 2;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:210" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=210 major=1 minor=0 bonus=2" );
        return true;
    }
    if ( value == 8211 || ( isstring( value ) && value == "8211" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["bandolier"] = 211;
        self.cp_bandolier_major = 1;
        self.cp_bandolier_minor = 1;
        self.cp_bandolier_bonus = 2;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:211" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=211 major=1 minor=1 bonus=2" );
        return true;
    }
    if ( value == 8220 || ( isstring( value ) && value == "8220" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["bandolier"] = 220;
        self.cp_bandolier_major = 2;
        self.cp_bandolier_minor = 0;
        self.cp_bandolier_bonus = 2;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:220" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=220 major=2 minor=0 bonus=2" );
        return true;
    }
    if ( value == 8221 || ( isstring( value ) && value == "8221" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["bandolier"] = 221;
        self.cp_bandolier_major = 2;
        self.cp_bandolier_minor = 1;
        self.cp_bandolier_bonus = 2;
        self setclientdvar( @"bo7_cp_bandolier_pick_ack", "accepted:221" );
        setdvar( @"bo7_cp_augments_transport", "perk=bandolier pick=221 major=2 minor=1 bonus=2" );
        return true;
    }
    return false;
}
// END GENERATED COOP bandolier

// BEGIN GENERATED COOP gautys_gold
// @coop_sync gautys_gold 4000
function cp_receive_generated_gautys_gold(channel, value)
{
    if (!isplayer(self) || !isdefined(value) || (channel != "perk_choice_purchase" && channel != "custom_perk_choice_purchase")) return false;
    if (value == 4000 || (isstring(value) && value == "4000"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["gautys_gold"] = 0;
        self.cp_gold_major = 0;
        self.cp_gold_minor = 0;
        self.cp_gold_bonus = 0;
        self setclientdvar(@"bo7_cp_gold_pick_ack", "accepted:0");
        return true;
    }
    if (value == 4001 || (isstring(value) && value == "4001"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["gautys_gold"] = 1;
        self.cp_gold_major = 0;
        self.cp_gold_minor = 1;
        self.cp_gold_bonus = 0;
        self setclientdvar(@"bo7_cp_gold_pick_ack", "accepted:1");
        return true;
    }
    if (value == 4010 || (isstring(value) && value == "4010"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["gautys_gold"] = 10;
        self.cp_gold_major = 1;
        self.cp_gold_minor = 0;
        self.cp_gold_bonus = 0;
        self setclientdvar(@"bo7_cp_gold_pick_ack", "accepted:10");
        return true;
    }
    if (value == 4011 || (isstring(value) && value == "4011"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["gautys_gold"] = 11;
        self.cp_gold_major = 1;
        self.cp_gold_minor = 1;
        self.cp_gold_bonus = 0;
        self setclientdvar(@"bo7_cp_gold_pick_ack", "accepted:11");
        return true;
    }
    if (value == 4020 || (isstring(value) && value == "4020"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["gautys_gold"] = 20;
        self.cp_gold_major = 2;
        self.cp_gold_minor = 0;
        self.cp_gold_bonus = 0;
        self setclientdvar(@"bo7_cp_gold_pick_ack", "accepted:20");
        return true;
    }
    if (value == 4021 || (isstring(value) && value == "4021"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["gautys_gold"] = 21;
        self.cp_gold_major = 2;
        self.cp_gold_minor = 1;
        self.cp_gold_bonus = 0;
        self setclientdvar(@"bo7_cp_gold_pick_ack", "accepted:21");
        return true;
    }
    if (value == 4030 || (isstring(value) && value == "4030"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["gautys_gold"] = 30;
        self.cp_gold_major = 3;
        self.cp_gold_minor = 0;
        self.cp_gold_bonus = 0;
        self setclientdvar(@"bo7_cp_gold_pick_ack", "accepted:30");
        return true;
    }
    if (value == 4031 || (isstring(value) && value == "4031"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["gautys_gold"] = 31;
        self.cp_gold_major = 3;
        self.cp_gold_minor = 1;
        self.cp_gold_bonus = 0;
        self setclientdvar(@"bo7_cp_gold_pick_ack", "accepted:31");
        return true;
    }
    if (value == 4100 || (isstring(value) && value == "4100"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["gautys_gold"] = 100;
        self.cp_gold_major = 0;
        self.cp_gold_minor = 0;
        self.cp_gold_bonus = 1;
        self setclientdvar(@"bo7_cp_gold_pick_ack", "accepted:100");
        return true;
    }
    if (value == 4110 || (isstring(value) && value == "4110"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["gautys_gold"] = 110;
        self.cp_gold_major = 1;
        self.cp_gold_minor = 0;
        self.cp_gold_bonus = 1;
        self setclientdvar(@"bo7_cp_gold_pick_ack", "accepted:110");
        return true;
    }
    if (value == 4120 || (isstring(value) && value == "4120"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["gautys_gold"] = 120;
        self.cp_gold_major = 2;
        self.cp_gold_minor = 0;
        self.cp_gold_bonus = 1;
        self setclientdvar(@"bo7_cp_gold_pick_ack", "accepted:120");
        return true;
    }
    if (value == 4130 || (isstring(value) && value == "4130"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["gautys_gold"] = 130;
        self.cp_gold_major = 3;
        self.cp_gold_minor = 0;
        self.cp_gold_bonus = 1;
        self setclientdvar(@"bo7_cp_gold_pick_ack", "accepted:130");
        return true;
    }
    return false;
}
// END GENERATED COOP gautys_gold

// BEGIN GENERATED COOP tortoise
// @coop_sync tortoise 7000
function cp_receive_generated_tortoise(channel, value)
{
    if (!isplayer(self) || !isdefined(value) || (channel != "perk_choice_purchase" && channel != "custom_perk_choice_purchase")) return false;
    if (value == 7000 || (isstring(value) && value == "7000"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["tortoise"] = 0;
        self.cp_tortoise_major = 0;
        self.cp_tortoise_minor = 0;
        self.cp_tortoise_bonus = 0;
        self setclientdvar(@"bo7_cp_tortoise_pick_ack", "accepted:0");
        return true;
    }
    if (value == 7001 || (isstring(value) && value == "7001"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["tortoise"] = 1;
        self.cp_tortoise_major = 0;
        self.cp_tortoise_minor = 1;
        self.cp_tortoise_bonus = 0;
        self setclientdvar(@"bo7_cp_tortoise_pick_ack", "accepted:1");
        return true;
    }
    if (value == 7002 || (isstring(value) && value == "7002"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["tortoise"] = 2;
        self.cp_tortoise_major = 0;
        self.cp_tortoise_minor = 2;
        self.cp_tortoise_bonus = 0;
        self setclientdvar(@"bo7_cp_tortoise_pick_ack", "accepted:2");
        return true;
    }
    if (value == 7010 || (isstring(value) && value == "7010"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["tortoise"] = 10;
        self.cp_tortoise_major = 1;
        self.cp_tortoise_minor = 0;
        self.cp_tortoise_bonus = 0;
        self setclientdvar(@"bo7_cp_tortoise_pick_ack", "accepted:10");
        return true;
    }
    if (value == 7011 || (isstring(value) && value == "7011"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["tortoise"] = 11;
        self.cp_tortoise_major = 1;
        self.cp_tortoise_minor = 1;
        self.cp_tortoise_bonus = 0;
        self setclientdvar(@"bo7_cp_tortoise_pick_ack", "accepted:11");
        return true;
    }
    if (value == 7012 || (isstring(value) && value == "7012"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["tortoise"] = 12;
        self.cp_tortoise_major = 1;
        self.cp_tortoise_minor = 2;
        self.cp_tortoise_bonus = 0;
        self setclientdvar(@"bo7_cp_tortoise_pick_ack", "accepted:12");
        return true;
    }
    if (value == 7020 || (isstring(value) && value == "7020"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["tortoise"] = 20;
        self.cp_tortoise_major = 2;
        self.cp_tortoise_minor = 0;
        self.cp_tortoise_bonus = 0;
        self setclientdvar(@"bo7_cp_tortoise_pick_ack", "accepted:20");
        return true;
    }
    if (value == 7021 || (isstring(value) && value == "7021"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["tortoise"] = 21;
        self.cp_tortoise_major = 2;
        self.cp_tortoise_minor = 1;
        self.cp_tortoise_bonus = 0;
        self setclientdvar(@"bo7_cp_tortoise_pick_ack", "accepted:21");
        return true;
    }
    if (value == 7022 || (isstring(value) && value == "7022"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["tortoise"] = 22;
        self.cp_tortoise_major = 2;
        self.cp_tortoise_minor = 2;
        self.cp_tortoise_bonus = 0;
        self setclientdvar(@"bo7_cp_tortoise_pick_ack", "accepted:22");
        return true;
    }
    if (value == 7100 || (isstring(value) && value == "7100"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["tortoise"] = 100;
        self.cp_tortoise_major = 0;
        self.cp_tortoise_minor = 0;
        self.cp_tortoise_bonus = 1;
        self setclientdvar(@"bo7_cp_tortoise_pick_ack", "accepted:100");
        return true;
    }
    if (value == 7102 || (isstring(value) && value == "7102"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["tortoise"] = 102;
        self.cp_tortoise_major = 0;
        self.cp_tortoise_minor = 2;
        self.cp_tortoise_bonus = 1;
        self setclientdvar(@"bo7_cp_tortoise_pick_ack", "accepted:102");
        return true;
    }
    if (value == 7110 || (isstring(value) && value == "7110"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["tortoise"] = 110;
        self.cp_tortoise_major = 1;
        self.cp_tortoise_minor = 0;
        self.cp_tortoise_bonus = 1;
        self setclientdvar(@"bo7_cp_tortoise_pick_ack", "accepted:110");
        return true;
    }
    if (value == 7112 || (isstring(value) && value == "7112"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["tortoise"] = 112;
        self.cp_tortoise_major = 1;
        self.cp_tortoise_minor = 2;
        self.cp_tortoise_bonus = 1;
        self setclientdvar(@"bo7_cp_tortoise_pick_ack", "accepted:112");
        return true;
    }
    if (value == 7120 || (isstring(value) && value == "7120"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["tortoise"] = 120;
        self.cp_tortoise_major = 2;
        self.cp_tortoise_minor = 0;
        self.cp_tortoise_bonus = 1;
        self setclientdvar(@"bo7_cp_tortoise_pick_ack", "accepted:120");
        return true;
    }
    if (value == 7122 || (isstring(value) && value == "7122"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["tortoise"] = 122;
        self.cp_tortoise_major = 2;
        self.cp_tortoise_minor = 2;
        self.cp_tortoise_bonus = 1;
        self setclientdvar(@"bo7_cp_tortoise_pick_ack", "accepted:122");
        return true;
    }
    if (value == 7200 || (isstring(value) && value == "7200"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["tortoise"] = 200;
        self.cp_tortoise_major = 0;
        self.cp_tortoise_minor = 0;
        self.cp_tortoise_bonus = 2;
        self setclientdvar(@"bo7_cp_tortoise_pick_ack", "accepted:200");
        return true;
    }
    if (value == 7201 || (isstring(value) && value == "7201"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["tortoise"] = 201;
        self.cp_tortoise_major = 0;
        self.cp_tortoise_minor = 1;
        self.cp_tortoise_bonus = 2;
        self setclientdvar(@"bo7_cp_tortoise_pick_ack", "accepted:201");
        return true;
    }
    if (value == 7210 || (isstring(value) && value == "7210"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["tortoise"] = 210;
        self.cp_tortoise_major = 1;
        self.cp_tortoise_minor = 0;
        self.cp_tortoise_bonus = 2;
        self setclientdvar(@"bo7_cp_tortoise_pick_ack", "accepted:210");
        return true;
    }
    if (value == 7211 || (isstring(value) && value == "7211"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["tortoise"] = 211;
        self.cp_tortoise_major = 1;
        self.cp_tortoise_minor = 1;
        self.cp_tortoise_bonus = 2;
        self setclientdvar(@"bo7_cp_tortoise_pick_ack", "accepted:211");
        return true;
    }
    if (value == 7220 || (isstring(value) && value == "7220"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["tortoise"] = 220;
        self.cp_tortoise_major = 2;
        self.cp_tortoise_minor = 0;
        self.cp_tortoise_bonus = 2;
        self setclientdvar(@"bo7_cp_tortoise_pick_ack", "accepted:220");
        return true;
    }
    if (value == 7221 || (isstring(value) && value == "7221"))
    {
        if (!isdefined(self.cp_picks)) self.cp_picks = [];
        self.cp_picks["tortoise"] = 221;
        self.cp_tortoise_major = 2;
        self.cp_tortoise_minor = 1;
        self.cp_tortoise_bonus = 2;
        self setclientdvar(@"bo7_cp_tortoise_pick_ack", "accepted:221");
        return true;
    }
    return false;
}
// END GENERATED COOP tortoise


function cp_native_toggle_init()
{
    level endon(#"game_ended");
    level.cp_disabled_native = [];
    if (getdvarint(@"bo7_cp_off_native_juggernog", 0) == 1) level.cp_disabled_native["specialty_juggernog"] = true;
    if (getdvarint(@"bo7_cp_off_native_quick_revive", 0) == 1) level.cp_disabled_native["specialty_quick_revive"] = true;
    if (getdvarint(@"bo7_cp_off_native_speedcola", 0) == 1) level.cp_disabled_native["specialty_speedcola"] = true;
    if (getdvarint(@"bo7_cp_off_native_staminup", 0) == 1) level.cp_disabled_native["specialty_staminup"] = true;
    if (getdvarint(@"bo7_cp_off_native_deadshot", 0) == 1) level.cp_disabled_native["specialty_deadshot"] = true;
    if (getdvarint(@"bo7_cp_off_native_elemental_pop", 0) == 1) level.cp_disabled_native["specialty_elemental_pop"] = true;
    if (getdvarint(@"bo7_cp_off_native_phd_flopper", 0) == 1) level.cp_disabled_native["specialty_phd_flopper"] = true;
    if (getdvarint(@"bo7_cp_off_native_death_perception", 0) == 1) level.cp_disabled_native["specialty_death_perception"] = true;
    if (getdvarint(@"bo7_cp_off_native_vulture_aid", 0) == 1) level.cp_disabled_native["specialty_vulture_aid"] = true;
    if (getdvarint(@"bo7_cp_off_native_m_mod", 0) == 1) level.cp_disabled_native["specialty_m_mod"] = true;
    if (getdvarint(@"bo7_cp_off_native_d_mod", 0) == 1) level.cp_disabled_native["specialty_d_mod"] = true;
    if (getdvarint(@"bo7_cp_off_native_w_mod", 0) == 1) level.cp_disabled_native["specialty_w_mod"] = true;
    if (getdvarint(@"bo7_cp_off_native_y_mod", 0) == 1) level.cp_disabled_native["specialty_y_mod"] = true;
    if (getdvarint(@"bo7_cp_off_native_z_mod", 0) == 1) level.cp_disabled_native["specialty_z_mod"] = true;
    level utility::flag_wait_all("StartGameTypeCallbackFinished", "zombie_perks_init_complete");
    if (level.cp_disabled_native.size == 0) return;
    level callback::add("zm_perk_obtained", &cp_native_toggle_obtained);
    level callback::add("currency_sub", &cp_native_toggle_refund);
    while (true)
    {
        foreach (player in level.players)
        {
            foreach (ref, disabled in level.cp_disabled_native)
            {
                if (isdefined(player) && isalive(player) && player zombie_perks::has_perk(ref))
                    player thread cp_native_toggle_remove(ref);
            }
        }
        wait 0.25;
    }
}

function cp_native_toggle_obtained(params)
{
    if (!isplayer(self) || !isdefined(params.specialtyperk)) return;
    foreach (ref, disabled in level.cp_disabled_native)
    {
        if (params.specialtyperk == ref || params.specialtyperk == getxhash(ref))
        {
            self thread cp_native_toggle_remove(ref);
            return;
        }
    }
}

function cp_native_toggle_remove(ref)
{
    self endon(#"disconnect");
    level endon(#"game_ended");
    if (!isdefined(self.cp_native_removing)) self.cp_native_removing = [];
    if (istrue(self.cp_native_removing[ref])) return;
    self.cp_native_removing[ref] = true;
    waitframe();
    if (self zombie_perks::has_perk(ref)) self zombie_perks::take_perk(ref);
    self.cp_native_removing[ref] = false;
}

function cp_native_toggle_refund(params)
{
    if (!isplayer(self) || !isdefined(params.amount) || params.amount <= 0 || !isdefined(params.info)) return;
    foreach (ref, disabled in level.cp_disabled_native)
    {
        if (params.info == ref || params.info == getxhash(ref))
        {
            self currency::add_currency_amount(params.currencytype, params.amount, #"disabled_perk_refund", ref);
            return;
        }
    }
}

// BEGIN GENERATED COOP jug2
// @coop_sync jug2 10000
function cp_receive_generated_jug2( channel, value )
{
    if ( !isplayer( self ) || !isdefined( value ) || ( channel != "perk_choice_purchase" && channel != "custom_perk_choice_purchase" ) ) return false;
    if ( value == 10000 || ( isstring( value ) && value == "10000" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["jug2"] = 0;
        self.cp_jug2_major = 0;
        self.cp_jug2_minor = 0;
        self.cp_jug2_bonus = 0;
        self setclientdvar( @"bo7_cp_jug2_pick_ack", "accepted:0" );
        setdvar( @"bo7_cp_augments_transport", "perk=jug2 pick=0 major=0 minor=0 bonus=0" );
        return true;
    }
    if ( value == 10010 || ( isstring( value ) && value == "10010" ) )
    {
        if ( !isdefined( self.cp_picks ) ) self.cp_picks = [];
        self.cp_picks["jug2"] = 10;
        self.cp_jug2_major = 1;
        self.cp_jug2_minor = 0;
        self.cp_jug2_bonus = 0;
        self setclientdvar( @"bo7_cp_jug2_pick_ack", "accepted:10" );
        setdvar( @"bo7_cp_augments_transport", "perk=jug2 pick=10 major=1 minor=0 bonus=0" );
        return true;
    }
    return false;
}
// END GENERATED COOP jug2
