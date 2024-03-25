require('chat')
require('logger')
require('tables')
config = require('config')
res = require('resources')
packets = require('packets')

_addon.name = 'lazy'
_addon.author = 'Brax'
_addon.version = '0.5'
_addon.commands = {'lazy'}

start_engine = true
isCasting = false
isBusy = 0
buffactive = {}
Action_Delay = 2

buffactive = {}

defaults = {}
defaults.spell = ""
defaults.spell_active = false
defaults.weaponskill = ""
defaults.weaponskill_active = false
defaults.autotarget = false
defaults.target = ""

settings = config.load(defaults)

local function split_string_by_comma(inputStr)
    local result = {}
    for match in (inputStr..','):gmatch("(.-)"..',') do
        table.insert(result, match)
    end
    return result
end


settings.targets = split_string_by_comma(settings.targets)

windower.register_event('incoming chunk', function(id, data)
    if id == 0x028 then
        local action_message = packets.parse('incoming', data)
		if action_message["Category"] == 4 then
			isCasting = false
		elseif action_message["Category"] == 8 then
			isCasting = true
			if action_message["Target 1 Action 1 Message"] == 0 then
				isCasting = false
				isBusy = Action_Delay
			end
		end
	end
end)

windower.register_event('outgoing chunk', function(id, data)
    if id == 0x015 then
        local action_message = packets.parse('outgoing', data)
		PlayerH = action_message["Rotation"]
	end
end)

windower.register_event('addon command', function (...)
	local args	= T{...}:map(string.lower)
	if args[1] == nil or args[1] == "help" then
		print("Help Info")
	elseif args[1] == "start" then
		windower.add_to_chat(2,"....Starting Lazy Helper....")
		start_engine = true
		engine()
	elseif args[1] == "stop" then
		windower.add_to_chat(2,"....Stopping Lazy Helper....")
		start_engine = false
	elseif args[1] == "reload" then
		windower.add_to_chat(2,"....Reloading Config....")
		config.reload(settings)
	elseif args[1] == "save" then
		config.save(settings,windower.ffxi.get_player().name)
	elseif args[1] == "test" then
		test()
	elseif args[1] == "show" then
		windower.add_to_chat(11,"Autotarget: "..tostring(settings.autotarget))
		windower.add_to_chat(11,"Spell: "..settings.spell)
		windower.add_to_chat(11,"Use Spell "..tostring(settings.spell_active))
		windower.add_to_chat(11,"Weaponskill: "..settings.weaponskill)
		windower.add_to_chat(11,"Use Weaponskill: "..tostring(settings.weaponskill_active))
		-- windower.add_to_chat(11,"Target:"..settings.target)
	elseif args[1] == "autotarget" then
		if args[2] == "on" then
			settings.autotarget = true
			windower.add_to_chat(3,"Autotarget: True")
		else
			settings.autotarget = false
			windower.add_to_chat(3,"Autotarget: False")
		end
    end
	-- elseif args[1] == "target" then
	-- 	settings.target = args[2]
	-- end
end)

function heading_to(X,Y)
	local X = X - windower.ffxi.get_mob_by_id(windower.ffxi.get_player().id).x
	local Y = Y - windower.ffxi.get_mob_by_id(windower.ffxi.get_player().id).y
	local H = math.atan2(X,Y)
	return H - 1.5708
end

function turn_to_target()
	local destX = windower.ffxi.get_mob_by_target('t').x
	local destY = windower.ffxi.get_mob_by_target('t').y
	local direction = math.abs(PlayerH - math.deg(heading_to(destX,destY)))
	if direction > 10 then
		windower.ffxi.turn(heading_to(destX,destY))
	end
end

function find_nearest_target(target)
	local id_targ = -1
	local dist_targ = -1
	local marray = windower.ffxi.get_mob_array()
	for key,mob in pairs(marray) do
		if contains(settings.targets, string.lower(mob['name'])) and mob["valid_target"] and mob["hpp"] == 100 then
			if dist_targ == -1 then
				id_targ = key
				dist_targ = math.sqrt(mob["distance"])
			elseif math.sqrt(mob["distance"]) < dist_targ then
				id_targ = key
				dist_targ = math.sqrt(mob["distance"])
			end
		end
	end
	return(id_targ)
end

function check_distance()
	local distance = windower.ffxi.get_mob_by_target('t').distance:sqrt()
	if distance > 3 then
		turn_to_target()
		windower.ffxi.run()
	else
		windower.ffxi.run(false)
	end
end

function test()
end

function engine()
	Buffs = windower.ffxi.get_player()["buffs"]
    table.reassign(buffactive,convert_buff_list(Buffs))

	if isBusy < 1 then
		pcall(combat)
	else
		isBusy = isBusy -1
	end
	if start_engine then
		coroutine.schedule(engine,1)
	end
end

function combat()
	-- is Engaged / combat
	if windower.ffxi.get_player().status == 1 then
		turn_to_target()
		check_distance()
		if windower.ffxi.get_player().vitals.tp >1000 and settings.weaponskill_active == true and windower.ffxi.get_mob_by_target('t').distance:sqrt() < 3.0 then
			windower.send_command(settings.weaponskill)
			isBusy = Action_Delay
		elseif can_cast_spell(settings.spell) and settings.spell_active == true then
			cast_spell(settings.spell)
		end
	elseif settings.autotarget == true then
		if find_nearest_target(settings.targets) > 0 then
			windower.ffxi.follow(find_nearest_target(settings.targets))
			if math.sqrt(windower.ffxi.get_mob_by_index(find_nearest_target(settings.targets)).distance) < 3 then
				-- windower.send_command("input /targetbnpc")
				target_nearest(settings.targets)
				windower.send_command("input /attack on")
			end
		end
	end
end

function can_cast_spell(spell)
	local result = false
	local myspell = res.spells:with('name',spell)
	Recasts = windower.ffxi.get_spell_recasts()
	if (Recasts[myspell.id] == 0) and (not isCasting) and (windower.ffxi.get_player().vitals.mp >= myspell.mp_cost) and (isBusy == 0) then
		result = true
	end
	return result
end

function can_cast_ability(ability)
	local result = false
	local myability = res.job_abilities:with('name',ability)
	Recasts = windower.ffxi.get_ability_recasts()
	print("Checking:"..myability.name)
	if (Recasts[myability.recast_id] == 0) and (not isCasting) and (isBusy == 0) then
		result = true
	end
	return result
end

function cast_spell(spell)
	Recasts = windower.ffxi.get_spell_recasts()
	local myspell = res.spells:with('name',spell)
	if Recasts[myspell.id] == 0 and not isCasting then
		windower.send_command(myspell.name)
		isBusy = Action_Delay
	end
end

function cast_ability(ability)
	Recasts = windower.ffxi.get_ability_recasts()
	local myability = res.job_abilities:with('name',ability)
	if Recasts[myability.recast_id] == 0 and not isCasting then
		windower.send_command(myability.name)
		isBusy = Action_Delay
	end
end


function convert_buff_list(bufflist)
    local buffarr = {}
    for i,v in pairs(bufflist) do
        if res.buffs[v] then -- For some reason we always have buff 255 active, which doesn't have an entry.
            local buff = res.buffs[v].english
            if buffarr[buff] then
                buffarr[buff] = buffarr[buff] +1
            else
                buffarr[buff] = 1
            end

            if buffarr[v] then
                buffarr[v] = buffarr[v] +1
            else
                buffarr[v] = 1
            end
        end
    end
    return buffarr
end

function target_nearest(target_names)
    local mobs = windower.ffxi.get_mob_array()
    local closest
    for _, mob in pairs(mobs) do
		if contains(settings.targets, string.lower(mob['name'])) and mob["valid_target"] and mob["hpp"] == 100 then
            if not closest or mob.distance < closest.distance then
                closest = mob
            end
        end
    end

    if not closest then
		windower.add_to_chat(2,"....Cannot find valid target....")
        return
    end

    local player = windower.ffxi.get_player()

    packets.inject(packets.new('incoming', 0x058, {
        ['Player'] = player.id,
        ['Target'] = closest.id,
        ['Player Index'] = player.index,
    }))

    if player.status == 1 then
        windower.send_command('wait 0.5; input /attack <t>')
    end
end



function contains(table, val)
    for _, value in ipairs(table) do
        if value == val then
            return true
        end
    end
    return false
end
