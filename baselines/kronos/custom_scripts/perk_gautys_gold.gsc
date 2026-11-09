// @augment major Golden Payout | Increases points from 1.25x to 1.35x while the perk is active.
// @augment major 15x Points | Multiplies points by 15 while Gauty's Gold is active (debug augment).
// @augment major Golden Refund | Purchases have a 50% chance to refund their full cost.
// @augment minor Golden Strike | Awards double points for melee kills.
#using scripts\common\callbacks;
#using scripts\common\utility;
#using scripts\mp\common\perks\zombie\zombie_perks;
#using scripts\mp\zm\points;
#using scripts\mp\currency;

#namespace perk_gautys_gold;

autoexec gautys_gold_init()
{
    setdvar( @"bo7_cp_gautys_gold_debug", "autoexec" );
    level thread gautys_gold_register_perk();
}

function gautys_gold_register_perk()
{
    level endon( #"game_ended" );
    level utility::flag_wait_all( "StartGameTypeCallbackFinished", "zombie_perks_init_complete" );

    if ( !level.zombie_perks_in_use )
    {
        logstring( "GAUTYS_GOLD registration skipped: Zombies perks are disabled" );
        return;
    }

    if ( !isdefined( level.cp_register ) || !isdefined( level.cp_register_native ) )
    {
        logstring( "GAUTYS_GOLD registration failed: custom perk manager is unavailable" );
        return;
    }

    def = [];
    def["id"] = "gautys_gold";
    def["creator"] = "Gauty";
    def["code"] = 82;
    def["name"] = "Gauty's Gold";
    def["description"] = "Earns 1.25x points while this perk is active. Equip augments for additional effects.";
    def["icon_material"] = "ui_icon_perks_zm_Gautys_Gold";
    def["price"] = 2500;
    def["drink_from"] = "specialty_juggernog";
    def["on_give"] = &give_gautys_gold_perk;
    def["on_take"] = &take_gautys_gold_perk;

    if ( !level [[ level.cp_register ]]( def ) )
    {
        logstring( "GAUTYS_GOLD registration failed: custom perk manager rejected the definition" );
        return;
    }

    level [[ level.cp_register_native ]]( "gautys_gold", level.cp_defs["gautys_gold"] );
    callback::add("currency_sub", &gautys_gold_refund_purchase);
    if ( !isdefined( level.gautys_gold_point_hook_running ) )
    {
        level.gautys_gold_point_hook_running = 1;
        level thread gautys_gold_point_hook_watch();
    }
    setdvar( @"bo7_cp_gautys_gold_debug", "registered" );
    logstring( "GAUTYS_GOLD queued for native perk registration" );
}

function gautys_gold_point_hook_watch()
{
    level endon( #"game_ended" );

    while ( 1 )
    {
        if ( !isdefined( level.modifyunifiedpointscallback ) )
        {
            if ( !isdefined( level.gautys_gold_point_hook_missing_logged ) )
            {
                level.gautys_gold_point_hook_missing_logged = 1;
                logstring( "GAUTYS_GOLD waiting for the Zombies point-score callback" );
            }
        }
        else if ( level.modifyunifiedpointscallback != &gautys_gold_modify_points )
        {
            level.gautys_gold_original_point_callback = level.modifyunifiedpointscallback;
            level.modifyunifiedpointscallback = &gautys_gold_modify_points;
            setdvar( @"bo7_cp_gautys_gold_debug", "point_hook_active" );
            logstring( "GAUTYS_GOLD point-score callback installed" );
        }

        wait 1;
    }
}

function gautys_gold_modify_points( points, event, player, objweapon, eventinfo )
{
    if ( !isdefined( level.gautys_gold_original_point_callback ) )
    {
        return points;
    }

    points = player [[ level.gautys_gold_original_point_callback ]]( points, event, player, objweapon, eventinfo );

    if ( isplayer( player ) &&
         isdefined( player.gautys_gold_melee_augment ) &&
         player.gautys_gold_melee_augment &&
         isdefined( eventinfo ) &&
         isdefined( eventinfo.smeansofdeath ) &&
         eventinfo.smeansofdeath == "MOD_MELEE" )
    {
        points = points * 2;
    }

    return int( points );
}

function give_gautys_gold_perk()
{
    self setclientdvar( @"bo7_cp_client_owned_gautys_gold", "1" );
    self.has_gautys_gold = 1;
    self.gautys_gold_major_augment = -1;
    self.gautys_gold_last_report = undefined;
    self.gautys_gold_melee_augment = 0;
    self points::set_point_scalar( 1.25, "gautys_gold" );
    self thread gautys_gold_apply_augments();
}

function take_gautys_gold_perk( b_pause, str_perk, str_result, n_slot )
{
    self setclientdvar( @"bo7_cp_client_owned_gautys_gold", "0" );
    self.has_gautys_gold = 0;
    self.gautys_gold_major_augment = 0;
    self.gautys_gold_melee_augment = 0;
    self notify( "take_gautys_gold" );
    self points::set_point_scalar( 1, "gautys_gold" );
}

function gautys_gold_apply_augments()
{
    self endon( #"death_or_disconnect" );
    self endon( "take_gautys_gold" );

    while ( self.has_gautys_gold == 1 )
    {
        n_pick = 0;
        n_major_augment = 0;
        n_minor_augment = 0;
        n_bonus_augment = 0;
        str_pick_source = "unsynced";
        if ( isdefined( self.cp_gold_major ) )
        {
            n_pick = self.cp_picks["gautys_gold"];
            n_major_augment = self.cp_gold_major;
            n_minor_augment = self.cp_gold_minor;
            n_bonus_augment = self.cp_gold_bonus;
            str_pick_source = "player_sync";
        }
        if ( n_major_augment != self.gautys_gold_major_augment )
        {
            n_point_multiplier = n_major_augment == 1 ? 1.35 : 1.25;
            if ( n_major_augment == 2 )
            {
                n_point_multiplier = 15;
            }
            self points::set_point_scalar( n_point_multiplier, "gautys_gold" );
            self.gautys_gold_major_augment = n_major_augment;
        }

        if ( n_minor_augment == 1 || n_bonus_augment == 1 )
        {
            self.gautys_gold_melee_augment = 1;
        }
        else
        {
            self.gautys_gold_melee_augment = 0;
        }
        report = "source=" + str_pick_source + " pick=" + n_pick + " major=" + n_major_augment + " minor=" + n_minor_augment + " bonus=" + n_bonus_augment + " scalar=" + n_point_multiplier;
        if ( !isdefined( self.gautys_gold_last_report ) || self.gautys_gold_last_report != report )
        {
            self.gautys_gold_last_report = report;
            setdvar( @"bo7_cp_gautys_gold_runtime", report );
        }
        wait 0.25;
    }
}

function gautys_gold_refund_purchase(params)
{
    if (!isplayer(self) || !istrue(self.has_gautys_gold) || (self.cp_gold_major ?? 0) != 3) return;
    if (!isdefined(params) || !isdefined(params.amount) || params.amount <= 0 || !isdefined(params.currencytype)) return;
    if (isdefined(level.cp_disabled_native) && isdefined(params.info))
    {
        foreach (ref, disabled in level.cp_disabled_native)
        {
            if (params.info == ref || params.info == getxhash(ref)) return;
        }
    }
    if (randomint(100) >= 50) return;
    self currency::add_currency_amount(params.currencytype, params.amount, #"gautys_gold_refund", params.info);
    setdvar(@"bo7_cp_gautys_gold_runtime", "purchase refunded: " + params.amount + " currency=" + params.currencytype);
}
