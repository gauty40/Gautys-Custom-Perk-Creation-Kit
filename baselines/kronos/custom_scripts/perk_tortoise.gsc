// @augment major Thorns | 50% of the damage a zombie does to you is reflected back to the zombie.
// @augment major Reinforced Shell | Take an additional 10% less damage while wearing armor.
// @augment minor Reserve Plate | Hold an extra armor plate in reserve.
// @augment minor Crusader's Ale | Your armor is fully repaired between rounds.

#using scripts\common\callbacks;
#using scripts\common\utility;
#using scripts\mp\armor;
#using scripts\mp\common\perks\zombie\zombie_perks;

#namespace perk_tortoise;

autoexec tortoise_init()
{
    setdvar( @"bo7_cp_tortoise_debug", "autoexec" );
    level thread tortoise_register_perk();
}

function tortoise_reduction()
{
    return 0.85;
}

function tortoise_thorns_share()
{
    return 5;
}

function tortoise_register_perk()
{
    level endon( #"game_ended" );
    level utility::flag_wait_all( "StartGameTypeCallbackFinished", "zombie_perks_init_complete" );

    if ( !level.zombie_perks_in_use )
    {
        return;
    }

    if ( !isdefined( level.cp_register ) || !isdefined( level.cp_register_native ) || !isdefined( level.cp_register_damage_mod ) )
    {
        logstring( "VICTORIOUS TORTOISE registration failed: custom perk manager is unavailable" );
        return;
    }

    def = [];
    def["id"] = "tortoise";
    def["creator"] = "Gauty";
    def["code"] = 73;
    def["name"] = "Victorious Tortoise";
    def["description"] = "Take 15% less damage while wearing armor.";
	def["icon_material"] = "ui_icon_perks_zm_tortoise";
    def["price"] = 2500;
    def["drink_from"] = "specialty_juggernog";
    def["on_give"] = &give_tortoise_perk;
    def["on_take"] = &take_tortoise_perk;

    if ( !level [[ level.cp_register ]]( def ) )
    {
        logstring( "VICTORIOUS TORTOISE registration rejected by the manager" );
        return;
    }

    level [[ level.cp_register_native ]]( "tortoise", level.cp_defs["tortoise"] );
    level [[ level.cp_register_damage_mod ]]( &tortoise_damage_mod );
    setdvar( @"bo7_cp_tortoise_debug", "registered" );
    logstring( "VICTORIOUS TORTOISE queued for native perk registration" );
}

function give_tortoise_perk()
{
    self notify( "specialty_tortoise_stop" );
    self setclientdvar( @"bo7_cp_client_owned_tortoise", "1" );
    self.cp_tortoise_plate_awarded = false;
    self thread tortoise_watch_augments();
    self thread tortoise_round_repair();
}

function tortoise_watch_augments()
{
    self endon( #"disconnect" );
    self endon( "specialty_tortoise_stop" );
    level endon( #"game_ended" );
    while ( true )
    {
        wait 0.1;
        if ( !self zombie_perks::has_perk( "specialty_tortoise" ) )
        {
            return;
        }
        n_major_augment = 0;
        if ( isdefined( self.cp_tortoise_major ) )
        {
            n_major_augment = self.cp_tortoise_major;
        }
        n_minor_augment = 0;
        if ( isdefined( self.cp_tortoise_minor ) )
        {
            n_minor_augment = self.cp_tortoise_minor;
        }
        n_bonus_augment = 0;
        if ( isdefined( self.cp_tortoise_bonus ) )
        {
            n_bonus_augment = self.cp_tortoise_bonus;
        }
        if ( !self.cp_tortoise_plate_awarded && ( n_minor_augment == 1 || n_bonus_augment == 1 ) && isalive( self ) )
        {
            self.cp_tortoise_plate_awarded = true;
            self tortoise_give_reserve_plate();
        }
    }
}

function tortoise_round_repair()
{
    self endon( #"disconnect" );
    self endon( "specialty_tortoise_stop" );
    level endon( #"game_ended" );

    while ( true )
    {
        level utility::waittill_any( "between_round_over", "round_end_finished", "on_round_end" );

        if ( !isalive( self ) || !self zombie_perks::has_perk( "specialty_tortoise" ) )
        {
            continue;
        }

        if ( (self.cp_tortoise_minor ?? 0) != 2 && (self.cp_tortoise_bonus ?? 0) != 2 )
        {
            continue;
        }

        n_max = self.maxarmorhealth ?? 0;
        n_now = self.armorhealth ?? 0;

        if ( n_now > 0 && n_now < n_max )
        {
            self armor::setarmorhealth( n_max );
            setdvar( @"bo7_cp_tortoise_runtime", "crusader's ale: armor repaired " + int( n_now ) + " -> " + int( n_max ) );
        }
    }
}

function tortoise_give_reserve_plate()
{
    n_before = self armor::function_22290101992e4874();
    self armor::function_164c824617d7e8d7( 1 );
    self armor::function_df9c3f3288ff004f( 1 );
    n_after = self armor::function_22290101992e4874();
    setdvar( @"bo7_cp_tortoise_runtime", "reserve plate: " + n_before + " -> " + n_after + " (max " + self armor::function_db9ebf086f67fe92() + ")" );
}

function tortoise_damage_mod( sparams, n_damage )
{
    if ( !isdefined( n_damage ) || n_damage <= 0 || !self zombie_perks::has_perk( "specialty_tortoise" ) )
    {
        return n_damage;
    }

    if ( ( self.armorhealth ?? 0 ) <= 0 )
    {
        return n_damage;
    }

    n_new_damage = int( max( 1, n_damage * ( 1 - tortoise_reduction() ) ) );

    n_major_augment = 0;
    if ( isdefined( self.cp_tortoise_major ) )
    {
        n_major_augment = self.cp_tortoise_major;
    }
    n_minor_augment = 0;
    if ( isdefined( self.cp_tortoise_minor ) )
    {
        n_minor_augment = self.cp_tortoise_minor;
    }
    n_bonus_augment = 0;
    if ( isdefined( self.cp_tortoise_bonus ) )
    {
        n_bonus_augment = self.cp_tortoise_bonus;
    }
    if (n_major_augment == 2) n_new_damage = max(1, int(n_new_damage * 0.9));
    n_reflected = 0;
    e_attacker = sparams.eattacker;

    if ( n_major_augment == 1 && isdefined( e_attacker ) && isagent( e_attacker ) && isalive( e_attacker ) )
    {
        n_reflected = n_new_damage * tortoise_thorns_share();
        e_attacker dodamage( n_reflected, e_attacker.origin, self, self, "MOD_UNKNOWN", "<explicitweaponnone>", "none", undefined, 65536 );
    }

    setdvar( @"bo7_cp_tortoise_runtime", "hit: " + int( n_damage ) + " -> " + n_new_damage + ", reflected " + int( n_reflected ) );
    return n_new_damage;
}

take_tortoise_perk( b_pause, str_perk, str_result, n_slot )
{
    self setclientdvar( @"bo7_cp_client_owned_tortoise", "0" );
    print( "VICTORIOUS TORTOISE take callback ran" );
    self notify( "specialty_tortoise_stop" );
}
