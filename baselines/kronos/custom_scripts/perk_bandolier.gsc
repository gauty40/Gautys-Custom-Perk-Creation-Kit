// @augment major Stowed Reload | Weapons you are not holding slowly refill their magazines from reserve ammo.
// @augment major Deep Pockets | Increases the extra reserve ammo from 50% to 100%.
// @augment minor Restock | At the end of every round, your weapons are refilled to the extended maximum.
// @augment minor Magazine Mule | Killing a zombie has a 5% chance to refill the magazine of your held weapon.

#using scripts\common\ai\aitypes\shared\zombie\zombie_utils;
#using scripts\common\callbacks;
#using scripts\common\utility;
#using scripts\mp\common\perks\zombie\zombie_perks;

#namespace perk_bandolier;

autoexec bandolier_init()
{
    setdvar( @"bo7_cp_bandolier_debug", "autoexec" );
    level thread bandolier_register_perk();
}

function bandolier_extra_fraction()
{
    return 0.5;
}

function bandolier_register_perk()
{
    level endon( #"game_ended" );
    level utility::flag_wait_all( "StartGameTypeCallbackFinished", "zombie_perks_init_complete" );

    if ( !level.zombie_perks_in_use )
    {
        return;
    }

    if ( !isdefined( level.cp_register ) || !isdefined( level.cp_register_native ) )
    {
        logstring( "BANDOLIER BANDIT registration failed: custom perk manager is unavailable" );
        return;
    }

    def = [];
    def["id"] = "bandolier";
    def["creator"] = "Gauty";
    def["code"] = 78;
    def["name"] = "Bandolier Bandit";
    def["description"] = "Your weapons hold 50% more reserve ammo. Equip augments for additional effects.";
    def["icon_material"] = "ui_icon_perks_zm_bandolier";
    def["price"] = 2500;
    def["drink_from"] = "specialty_juggernog";
    def["on_give"] = &give_bandolier_perk;
    def["on_take"] = &take_bandolier_perk;

    if ( !level [[ level.cp_register ]]( def ) )
    {
        logstring( "BANDOLIER BANDIT registration rejected by the manager" );
        return;
    }

    level [[ level.cp_register_native ]]( "bandolier", level.cp_defs["bandolier"] );
    zombie_utils::register_zombie_agent_damage_callback( &bandolier_on_zombie_damage );
    setdvar( @"bo7_cp_bandolier_debug", "registered" );
    logstring( "BANDOLIER BANDIT queued for native perk registration" );
}

give_bandolier_perk()
{
    self setclientdvar( @"bo7_cp_client_owned_bandolier", "1" );
    print( "BANDOLIER BANDIT give callback ran" );
    self.bb_prev = [];
    self thread bandolier_loop();
    self thread bandolier_round_restock();
}

function bandolier_extra_now()
{
    n_major_augment = 0;
    if ( isdefined( self.cp_bandolier_major ) )
    {
        n_major_augment = self.cp_bandolier_major;
    }
    n_minor_augment = 0;
    if ( isdefined( self.cp_bandolier_minor ) )
    {
        n_minor_augment = self.cp_bandolier_minor;
    }
    n_bonus_augment = 0;
    if ( isdefined( self.cp_bandolier_bonus ) )
    {
        n_bonus_augment = self.cp_bandolier_bonus;
    }

    if ( n_major_augment == 2 )
    {
        return 1.0;
    }

    return bandolier_extra_fraction();
}

function bandolier_loop()
{
    self endon( #"disconnect" );
    self endon( "specialty_bandolier_stop" );
    level endon( #"game_ended" );

    n_tick = 0;

    while ( true )
    {
        wait 0.5;
        n_tick = n_tick + 1;

        if ( !isalive( self ) )
        {
            continue;
        }

        n_major_augment = 0;
        if ( isdefined( self.cp_bandolier_major ) )
        {
            n_major_augment = self.cp_bandolier_major;
        }
        n_minor_augment = 0;
        if ( isdefined( self.cp_bandolier_minor ) )
        {
            n_minor_augment = self.cp_bandolier_minor;
        }
        n_bonus_augment = 0;
        if ( isdefined( self.cp_bandolier_bonus ) )
        {
            n_bonus_augment = self.cp_bandolier_bonus;
        }
        n_extra = self bandolier_extra_now();
        w_current = self getcurrentweapon();
        a_weapons = self getweaponslistprimaries();

        foreach ( w_weapon in a_weapons )
        {
            if ( !isdefined( w_weapon ) || w_weapon == level.weaponnone )
            {
                continue;
            }

            self bandolier_extend_stock( w_weapon, n_extra );

            if ( n_major_augment == 1 && w_weapon != w_current && ( n_tick % 2 ) == 0 )
            {
                n_clip = self getweaponammoclip( w_weapon );
                n_size = weaponclipsize( w_weapon );
                n_stock = self getweaponammostock( w_weapon );

                if ( n_clip < n_size && n_stock > 0 )
                {
                    self setweaponammoclip( w_weapon, n_clip + 1 );
                    self setweaponammostock( w_weapon, n_stock - 1 );
                }
            }
        }
    }
}

function bandolier_extend_stock( w_weapon, n_extra )
{
    n_normal = utility::get_max_stock_ammo( w_weapon, 0 );

    if ( !isdefined( n_normal ) || n_normal <= 0 )
    {
        return;
    }

    n_stock = self getweaponammostock( w_weapon );
    n_extended = int( n_normal * ( 1 + n_extra ) );
    str_key = "" + w_weapon.basename;
    n_prev = self.bb_prev[ str_key ];

    if ( !isdefined( n_prev ) )
    {

        n_new_stock = int( min( n_stock + ( n_extended - n_normal ), n_extended ) );

        if ( n_new_stock > n_stock )
        {
            self setweaponammostock( w_weapon, n_new_stock );
            n_stock = n_new_stock;
        }
    }
    else if ( n_stock >= n_normal && n_stock < n_extended && n_stock != n_prev && ( n_stock == n_normal || n_prev < n_normal ) )
    {

        self setweaponammostock( w_weapon, n_extended );
        n_stock = n_extended;
    }

    self.bb_prev[ str_key ] = n_stock;
}

function bandolier_round_restock()
{
    self endon( #"disconnect" );
    self endon( "specialty_bandolier_stop" );
    level endon( #"game_ended" );

    while ( true )
    {
        level utility::waittill_any( "between_round_over", "round_end_finished", "on_round_end" );

        n_major_augment = 0;
        if ( isdefined( self.cp_bandolier_major ) )
        {
            n_major_augment = self.cp_bandolier_major;
        }
        n_minor_augment = 0;
        if ( isdefined( self.cp_bandolier_minor ) )
        {
            n_minor_augment = self.cp_bandolier_minor;
        }
        n_bonus_augment = 0;
        if ( isdefined( self.cp_bandolier_bonus ) )
        {
            n_bonus_augment = self.cp_bandolier_bonus;
        }

        if ( ( n_minor_augment != 1 && n_bonus_augment != 1 ) || !isalive( self ) )
        {
            continue;
        }

        n_extra = self bandolier_extra_now();

        foreach ( w_weapon in self getweaponslistprimaries() )
        {
            n_normal = utility::get_max_stock_ammo( w_weapon, 0 );

            if ( !isdefined( w_weapon ) || w_weapon == level.weaponnone || !isdefined( n_normal ) || n_normal <= 0 )
            {
                continue;
            }

            n_extended = int( n_normal * ( 1 + n_extra ) );
            self setweaponammostock( w_weapon, n_extended );
            self.bb_prev[ "" + w_weapon.basename ] = n_extended;
        }

        setdvar( @"bo7_cp_bandolier_runtime", "restock: weapons refilled to the extended maximum" );
    }
}

function bandolier_on_zombie_damage( params )
{
    n_damage = params.idamage;
    e_attacker = params.eattacker;

    if ( !isdefined( n_damage ) || !isplayer( e_attacker ) || !e_attacker zombie_perks::has_perk( "specialty_bandolier" ) )
    {
        return n_damage;
    }

    n_major_augment = 0;
    if ( isdefined( e_attacker.cp_bandolier_major ) )
    {
        n_major_augment = e_attacker.cp_bandolier_major;
    }
    n_minor_augment = 0;
    if ( isdefined( e_attacker.cp_bandolier_minor ) )
    {
        n_minor_augment = e_attacker.cp_bandolier_minor;
    }
    n_bonus_augment = 0;
    if ( isdefined( e_attacker.cp_bandolier_bonus ) )
    {
        n_bonus_augment = e_attacker.cp_bandolier_bonus;
    }

    if ( ( n_minor_augment != 2 && n_bonus_augment != 2 ) || n_damage < self.health || isdefined( self.bb_counted ) )
    {
        return n_damage;
    }

    self.bb_counted = 1;

    if ( randomint( 100 ) < 5 )
    {
        w_current = e_attacker getcurrentweapon();
        e_attacker setweaponammoclip( w_current, weaponclipsize( w_current ) );
        setdvar( @"bo7_cp_bandolier_runtime", "magazine mule: magazine refilled" );
    }

    return n_damage;
}

take_bandolier_perk( b_pause, str_perk, str_result, n_slot )
{
    self setclientdvar( @"bo7_cp_client_owned_bandolier", "0" );
    print( "BANDOLIER BANDIT take callback ran" );
    self notify( "specialty_bandolier_stop" );
}
