// @augment major Chain Lightning | The reload shock can chain between zombies.
// @augment major Static Salvage | Zombies killed by the electric shock have a chance to give you an armor plate.
// @augment minor Quick Charge | Cooldown time reduced by 50%.
// @augment minor Muscle Milk | Melee hits on zombies also set off the electric shock (same cooldown).
// @augment minor High Voltage | The electric shock deals 5% more damage.
#using scripts\common\ai\aitypes\shared\zombie\zombie_utils;
#using scripts\common\callbacks;
#using scripts\common\status_effects\effect_stun;
#using scripts\common\utility;
#using scripts\mp\armor;
#using scripts\mp\common\perks\zombie\zombie_perks;

#namespace perk_electric_cherry;

autoexec electric_cherry_init()
{
    level thread electric_cherry_register_perk();

    electric_cherry_load_fx();
}

function electric_cherry_bolt_fx_name()
{
    return "vfx_sat_zm_weapons_tesla_elec_bolt_01_purple_ztron";
}

function electric_cherry_load_fx()
{
    level._effect["electric_cherry_player_shock"] = loadfxasset("vfx_jup_ob_gameplay_zm_tesla_shock_zmb");
    level._effect["electric_cherry_chain_bolt"] = loadfxasset( electric_cherry_bolt_fx_name() );
}

function electric_cherry_cooldown_ms()
{
    return 15000;
}

function electric_cherry_plate_chance()
{
    return 75;
}

function electric_cherry_radius()
{
    return 400;
}

function electric_cherry_outer_ring_fraction()
{
    return 0.25;
}

function electric_cherry_chain_radius()
{
    return 250;
}

function electric_cherry_chain_hops()
{
    return 3;
}

function electric_cherry_register_perk()
{
    level endon( #"game_ended" );
    level utility::flag_wait_all( "StartGameTypeCallbackFinished", "zombie_perks_init_complete" );

    if ( !level.zombie_perks_in_use )
    {
        return;
    }

    if ( !isdefined( level.cp_register ) || !isdefined( level.cp_register_native ) )
    {
        logstring( "ELECTRIC CHERRY registration failed: custom perk manager is unavailable" );
        return;
    }

    def = [];
    def["id"] = "electric_cherry";
    def["creator"] = "Gauty";
    def["code"] = 72;
    def["name"] = "Electric Cherry";
    def["description"] = "Reloading shocks nearby zombies for 50% of their max health and stuns survivors for 2 seconds (15 second cooldown). Equip augments for additional effects.";
    def["icon_material"] = "ui_icons_perks_zm_electric_cherry";
    def["price"] = 2500;
    def["drink_from"] = "specialty_juggernog";
    def["on_give"] = &give_electric_cherry_perk;
    def["on_take"] = &take_electric_cherry_perk;

    if ( !level [[ level.cp_register ]]( def ) )
    {
        logstring( "ELECTRIC CHERRY registration rejected by the manager" );
        return;
    }

    level [[ level.cp_register_native ]]( "electric_cherry", level.cp_defs["electric_cherry"] );
    zombie_utils::register_zombie_agent_damage_callback( &electric_cherry_on_zombie_damage );
    logstring( "ELECTRIC CHERRY queued for native perk registration" );
}

give_electric_cherry_perk()
{
    self setclientdvar( @"bo7_cp_client_owned_electric_cherry", "1" );
    print( "ELECTRIC CHERRY give callback ran" );
    self thread electric_cherry_watch_reload();
}

function electric_cherry_watch_reload()
{
    self endon( #"disconnect" );
    level endon( #"game_ended" );
    self endon( "specialty_electric_cherry_stop" );

    while ( true )
    {
        self waittill( #"reload_start" );
        self electric_cherry_try_fire();
    }
}

function electric_cherry_on_zombie_damage( params )
{
    n_damage = params.idamage;
    e_attacker = params.eattacker;

    if ( !isdefined( n_damage ) || !isplayer( e_attacker ) || !isdefined( params.smeansofdeath ) )
    {
        return n_damage;
    }

    if ( !issubstr( params.smeansofdeath, "MELEE" ) || !e_attacker zombie_perks::has_perk( "specialty_electric_cherry" ) )
    {
        return n_damage;
    }

    n_major_augment = 0;
    if ( isdefined( e_attacker.cp_electric_cherry_major ) )
    {
        n_major_augment = e_attacker.cp_electric_cherry_major;
    }
    n_minor_augment = 0;
    if ( isdefined( e_attacker.cp_electric_cherry_minor ) )
    {
        n_minor_augment = e_attacker.cp_electric_cherry_minor;
    }
    n_bonus_augment = 0;
    if ( isdefined( e_attacker.cp_electric_cherry_bonus ) )
    {
        n_bonus_augment = e_attacker.cp_electric_cherry_bonus;
    }

    if ( n_minor_augment == 2 || n_bonus_augment == 2 )
    {
        e_attacker thread electric_cherry_try_fire();
    }

    return n_damage;
}

function electric_cherry_try_fire()
{
    self endon( #"disconnect" );

    if ( !isalive( self ) || !self zombie_perks::has_perk( "specialty_electric_cherry" ) )
    {
        return;
    }

    n_now = gettime();

    if ( isdefined( self.ec_ready_at ) && n_now < self.ec_ready_at )
    {
        setdvar( @"bo7_cp_cherry_runtime", "cooldown " + int( ( self.ec_ready_at - n_now ) / 100 ) + " (x100ms) left" );
        return;
    }

    n_major_augment = 0;
    if ( isdefined( self.cp_electric_cherry_major ) )
    {
        n_major_augment = self.cp_electric_cherry_major;
    }
    n_minor_augment = 0;
    if ( isdefined( self.cp_electric_cherry_minor ) )
    {
        n_minor_augment = self.cp_electric_cherry_minor;
    }
    n_bonus_augment = 0;
    if ( isdefined( self.cp_electric_cherry_bonus ) )
    {
        n_bonus_augment = self.cp_electric_cherry_bonus;
    }

    n_cooldown = electric_cherry_cooldown_ms();

    if ( n_minor_augment == 1 || n_bonus_augment == 1 )
    {
        n_cooldown = int( n_cooldown / 2 );
    }

    self.ec_ready_at = n_now + n_cooldown;
    self thread electric_cherry_player_activation_fx();

    n_damage_scale = 0.5;

    if ( n_minor_augment == 3 || n_bonus_augment == 3 )
    {
        n_damage_scale = 0.5 * 1.05;
    }

    b_plate = n_major_augment == 2;
    level.cp_cherry_chain_id = ( level.cp_cherry_chain_id ?? 0 ) + 1;
    n_chain_id = level.cp_cherry_chain_id;

    setdvar( @"bo7_cp_cherry_runtime", "fired major=" + n_major_augment + " minor=" + n_minor_augment + " cooldown_ms=" + n_cooldown + " bonus=" + n_bonus_augment );

    b_chain = n_major_augment == 1;
    a_inner = [];
    a_outer = [];
    n_radius = electric_cherry_radius();
    n_outer_start = n_radius * ( 1 - electric_cherry_outer_ring_fraction() );
    zombies = getaiarrayinradius( self.origin, n_radius );

    foreach ( zombie in zombies )
    {
        if ( !isagent( zombie ) || !isalive( zombie ) )
        {
            continue;
        }

        if ( b_chain && distance( self.origin, zombie.origin ) >= n_outer_start )
        {
            a_outer[ a_outer.size ] = zombie;
            continue;
        }

        self electric_cherry_shock( zombie, n_damage_scale, b_plate, n_chain_id );
        a_inner[ a_inner.size ] = zombie;
    }

    if ( b_chain )
    {
        setdvar( @"bo7_cp_cherry_runtime", "fired chain: " + a_inner.size + " hit directly, " + a_outer.size + " left for the chain" );
        self thread electric_cherry_chain( a_inner, a_outer, n_damage_scale, b_plate, n_chain_id );
    }
}

function electric_cherry_shock( zombie, n_damage_scale, b_plate, n_chain_id )
{
    zombie.ec_chain_mark = n_chain_id;
    n_base_health = zombie.maxhealth;

    if ( !isdefined( n_base_health ) || n_base_health <= 0 )
    {
        n_base_health = zombie.health;
    }

    n_damage = n_base_health * n_damage_scale;
    zombie dodamage( n_damage, zombie.origin, self, self, "MOD_ELEMENTAL_ELEC", "<explicitweaponnone>", "none", undefined, 65536 );
    if ( b_plate )
    {
        self thread electric_cherry_plate_check( zombie );
    }
    if ( !isdefined( zombie ) || !isalive( zombie ) )
    {
        return;
    }
    zombie thread effect_stun::stun( "electric_cherry", 2, self, "shocked_on", undefined, "electrical" );
    zombie utility::function_32b24db3127bff40( "shocked_lightning_electric_cherry", "shocked_on" );
    zombie notify( "electric_cherry_custom_shock_stop" );
    zombie thread electric_cherry_shock_fx_off();

}

function electric_cherry_chain( a_frontier, a_outer, n_damage_scale, b_plate, n_chain_id )
{
    self endon( #"disconnect" );
    level endon( #"game_ended" );

    n_total_links = 0;
    n_hops_done = 0;

    for ( n_hop = 0; n_hop < electric_cherry_chain_hops(); n_hop++ )
    {
        wait 0.3;
        n_hops_done = n_hops_done + 1;
        a_next = [];

        foreach ( source in a_frontier )
        {
            if ( !isdefined( source ) )
            {
                continue;
            }

            a_near = getaiarrayinradius( source.origin, electric_cherry_chain_radius() );

            foreach ( zombie in a_near )
            {
                if ( !isagent( zombie ) || !isalive( zombie ) )
                {
                    continue;
                }

                if ( isdefined( zombie.ec_chain_mark ) && zombie.ec_chain_mark == n_chain_id )
                {
                    continue;
                }

                self thread electric_cherry_bolt( source, zombie );
                self electric_cherry_shock( zombie, n_damage_scale, b_plate, n_chain_id );
                a_next[ a_next.size ] = zombie;
                n_total_links = n_total_links + 1;
            }
        }

        if ( n_hop == 0 )
        {
            foreach ( zombie in a_outer )
            {
                if ( !isdefined( zombie ) || !isalive( zombie ) )
                {
                    continue;
                }

                if ( isdefined( zombie.ec_chain_mark ) && zombie.ec_chain_mark == n_chain_id )
                {
                    continue;
                }

                self thread electric_cherry_bolt( self, zombie );
                self electric_cherry_shock( zombie, n_damage_scale, b_plate, n_chain_id );
                a_next[ a_next.size ] = zombie;
                n_total_links = n_total_links + 1;
            }
        }

        if ( a_next.size == 0 )
        {
            break;
        }

        a_frontier = a_next;
    }

    setdvar( @"bo7_cp_cherry_runtime", "chain finished: " + n_total_links + " jumps over " + n_hops_done + " hop(s)" );
}

function electric_cherry_bolt( ent_from, ent_to )
{
    if ( !isdefined( level._effect["electric_cherry_chain_bolt"] ) || !isdefined( ent_from ) || !isdefined( ent_to ) )
    {
        return;
    }

    fx = level._effect["electric_cherry_chain_bolt"];
    if ( isdefined( level._effect["tesla_storm_beam_ai_effect"] ) )
    {
        fx = level._effect["tesla_storm_beam_ai_effect"];
    }
    e_bolt_start = utility::spawn_tag_origin( ent_from.origin + ( 0, 0, 48 ) );
    e_bolt_end = utility::spawn_tag_origin( ent_to.origin + ( 0, 0, 48 ) );
    e_bolt_start show();
    e_bolt_end show();
    e_bolt = playfxontagsbetweenclients( fx, e_bolt_start, "tag_origin", e_bolt_end, "tag_origin" );
    wait 0.5;
    if ( isdefined( e_bolt ) )
    {
        e_bolt delete();
    }
    e_bolt_start delete();
    e_bolt_end delete();
}

function electric_cherry_plate_check( zombie )
{
    self endon( #"disconnect" );
    wait 0.4;

    if ( isdefined( zombie ) && isalive( zombie ) )
    {
        return;
    }

    if ( randomint( 100 ) >= electric_cherry_plate_chance() )
    {
        return;
    }

    n_plates = self armor::function_22290101992e4874();
    n_max_plates = self armor::function_db9ebf086f67fe92();

    if ( n_plates >= n_max_plates )
    {
        setdvar( @"bo7_cp_cherry_runtime", "plate roll won but plates are full" );
        return;
    }

    self armor::function_164c824617d7e8d7( 1 );
    self armor::function_df9c3f3288ff004f( 1 );
    setdvar( @"bo7_cp_cherry_runtime", "armor plate given" );
}

function electric_cherry_shock_fx_off()
{
    self endon( #"death" );
    self endon( "electric_cherry_custom_shock_stop" );
    wait 2;
    self utility::function_32b24db3127bff40( "shocked_lightning_electric_cherry", "shocked_off" );
}

take_electric_cherry_perk( b_pause, str_perk, str_result, n_slot )
{
    self setclientdvar( @"bo7_cp_client_owned_electric_cherry", "0" );
    print( "ELECTRIC CHERRY take callback ran" );
    self notify( "specialty_electric_cherry_stop" );
}

function electric_cherry_player_activation_fx()
{
    self endon(#"disconnect");
    level endon(#"game_ended");
    self utility::function_32b24db3127bff40("electric_cherry_fx", "electric_cherry_fx_on");
    fx = level._effect["electric_cherry_player_shock"];
    tag = "tag_origin";
    if (self tagexists("j_spine4")) tag = "j_spine4";
    if (isdefined(fx)) playfxontag(fx, self, tag);
    wait 1.5;
    if (isdefined(self))
    {
        self utility::function_32b24db3127bff40("electric_cherry_fx", "electric_cherry_fx_off");
        if (isdefined(fx)) stopfxontag(fx, self, tag);
    }
}
