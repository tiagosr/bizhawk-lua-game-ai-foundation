-- Sonic 3

require 'class'
require 'bt'

----
-- variable locations
----

local level_layout_base = 0x8000
local object_attribute_table_base = 0xb000

----

----

local sonic_bb = {}
local sonic_tree = BehaviorTree(
	BTSequence("Main", {

		}))

console.log("Started!")

while true do
	sonic_tree:tick(sonic_bb)
	sonic_tree:draw(10, 10)
	emu.frameadvance()
end