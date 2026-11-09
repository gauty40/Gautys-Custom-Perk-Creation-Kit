// @augment major Moon Hop | Jumping reduces your gravity by 50% for 5 seconds.
#using scripts\common\callbacks;
#using scripts\common\utility;
#using scripts\mp\common\perks\zombie\zombie_perks;

#namespace perk_jug2;

autoexec jug2_init()
{
    level thread jug2_register_perk();
}

function jug2_register_perk()
{
    level endon( #"game_ended" );
    level utility::flag_wait_all( "StartGameTypeCallbackFinished", "zombie_perks_init_complete" );

    if ( !level.zombie_perks_in_use )
    {
        return;
    }

    if ( !isdefined( level.cp_register ) || !isdefined( level.cp_register_native ) )
    {
        logstring( "JUG2 registration failed: custom perk manager is unavailable" );
        return;
    }

    def = [];
    def["id"] = "jug2";
    def["creator"] = "Gauty";
    def["code"] = 71;
    def["name"] = "Roo Brew";
    def["description"] = "Jump five times as high. Equip Moon Hop to reduce gravity for 5 seconds after jumping.";

    def["icon_material"] = "ui_icons_perks_zm_roo_brew";
    def["price"] = 2500;
    def["drink_from"] = "specialty_juggernog";
    def["on_give"] = &give_jug2_perk;
    def["on_take"] = &take_jug2_perk;

    if ( !level [[ level.cp_register ]]( def ) )
    {
        logstring( "JUG2 registration rejected by the manager" );
        return;
    }

    level [[ level.cp_register_native ]]( "jug2", level.cp_defs["jug2"] );
    level callback::add(#"jump_begin", &roo_brew_on_jump);
    print( "JUG2 queued for native perk registration" );
    logstring( "JUG2 queued for native perk registration" );
}

function give_jug2_perk()
{
    self roo_brew_reset_gravity();
    self notify("roo_brew_stop");
    self setclientdvar(@"bo7_cp_client_owned_jug2", "1");
    self setjumpheightscale(5);
    self thread roo_brew_gravity_watch();
}

function roo_brew_on_jump(params)
{
    if (!isplayer(self) || !isalive(self) || istrue(self.inlaststand)) return;
    if (!self zombie_perks::has_perk("specialty_jug2") || (self.cp_jug2_major ?? 0) != 1) return;
    self.roo_brew_gravity_until = gettime() + 5000;
    self.roo_brew_gravity_active = true;
    self setgravityscale(0.5);
}

function roo_brew_reset_gravity()
{
    if (istrue(self.roo_brew_gravity_active)) self setgravityscale(1);
    self.roo_brew_gravity_active = false;
    self.roo_brew_gravity_until = undefined;
}

function roo_brew_gravity_watch()
{
    self endon(#"disconnect");
    self endon("roo_brew_stop");
    level endon(#"game_ended");
    while (true)
    {
        if (!self zombie_perks::has_perk("specialty_jug2"))
        {
            self roo_brew_reset_gravity();
            return;
        }
        if (istrue(self.roo_brew_gravity_active))
        {
            if (!isalive(self) || istrue(self.inlaststand) || (self.cp_jug2_major ?? 0) != 1 || gettime() >= self.roo_brew_gravity_until)
                self roo_brew_reset_gravity();
        }
        wait 0.05;
    }
}

function take_jug2_perk(b_pause, str_perk, str_result, n_slot)
{
    self roo_brew_reset_gravity();
    self notify("roo_brew_stop");
    self setclientdvar(@"bo7_cp_client_owned_jug2", "0");
    self setjumpheightscale(1);
}
