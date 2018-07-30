
require 'class'

local Success = true
local Failure = false
local Running = class(function(r, cb)
	r.cb = cb
end)
function Running:tick(tree, ctx)
	return self.cb(tree, ctx)
end
local Invalid = class(function(i, msg)
	i.msg = msg
end)
function Invalid:tick(tree, ctx)
	gui.addmessage("Invalid BT state - "..self.msg)
end

--------------------------------
-- Behavior Tree Nodes - Generic
--------------------------------



BTNode = class(function(n, t, name)
	n.name = name
	n.type = t
end)
function BTNode:tick(tree, ctx)
	return tree:invalid(self, "BTNode:tick not specialized for "..self)
end
function BTNode:__tostring()
	return self.type.."("..self.name..")"
end

function BTNode:draw_children(x, y)

end
function BTNode:draw(x, y)
	local bw, bh = self:bounds()
	local w, h = self:box_measure()
	gui.drawRectangle(x, y+(bh/2)-(h/2), w, h, 0xffff0000)
	gui.drawString(x+1, y+(bh/2)-7, self.name)
	self:draw_children(x+w, y)
end

function BTNode:box_measure()
	return 8*(#self.name) + 2, 14
end

function BTNode:bounds()
	return 8*(#self.name) + 6, 18
end


BTComposite = class(BTNode, function(seq, t, name, children)
	BTNode.init(seq, t, name)
	seq.children = children or {}
end)
function BTComposite:tick(tree, ctx)
	-- start recursing in the childen list
	return self:child_tick(tree, ctx, 1)
end
function BTComposite:child_tick(tree, ctx, child_idx)
	return tree:invalid(self, "BTComposite:child_tick not specialized for "..self)
end

function BTComposite:bounds()
	local acc_w, acc_h = 0, 0
	for i,child in ipairs(self.children) do
		local w, h = child:bounds()
		if w > acc_w then acc_w = w end
		acc_h = acc_h + h
	end
	local w, h = self:box_measure()
	if acc_h < h then acc_h = h end
	return acc_w + 10 + w, acc_h
end

function BTComposite:draw_children(x, y)
	local b_w, b_h = self:bounds()
	for i,child in ipairs(self.children) do
		local c_w, c_h = child:bounds()
		gui.drawLine(x, y + b_h/2, x+10, y + (c_h/2))
		child:draw(x+10, y)
		y = y + c_h
	end
end

BTSequence = class(BTComposite, function(seq, name, children)
	BTComposite.init(seq, "BTSequence", name, children)
end)

function BTSequence:child_tick(tree, ctx, child_idx)
	if #self.children < child_idx then
		return tree:success(self)
	end
	local ret = self.children[child_idx]:tick(tree, ctx)
	if ret == Failure then
		return tree:failure(self)
	elseif ret == Success then
		return self:child_tick(tree, ctx, child_idx+1)
	elseif ret:is_a(Running) then
		return tree:running(self, function(tree, ctx) return self:child_tick(tree, ctx, child_idx) end)
	else
		return tree:returned(self, ret)
	end
end

BTSelector = class(BTComposite, function(seq, name, children)
	BTComposite.init(seq, "BTSelector", name, children)
end)

function BTSelector:child_tick(tree, ctx, child_idx)
	if #self.children < child_idx then
		return tree:failure(self)
	end
	local ret = self.children[child_idx]:tick(tree, ctx)
	if ret == Success then
		return tree:success(self)
	elseif ret == Failure then
		return self:child_tick(tree, ctx, child_idx+1)
	elseif ret:is_a(Running) then
		return tree:running(self, function(tree, ctx) return self:child_tick(tree, ctx, child_idx) end)
	else
		return tree:returned(self, ret)
	end
end

BTDecorator = class(BTNode, function(d, t, name, child)
	BTNode.init(d, t, name)
	d.child = child
end)
function BTDecorator:decorate(tree, node, ctx)
	return tree:invalid(self, "BTDecorator:decorate not specialized for "..self)
end
function BTDecorator:tick(tree, ctx)
	return self:decorate(tree, self.child, ctx)
end

function BTDecorator:draw_children(x, y)
	local b_w, b_h = self:bounds()
	local c_w, c_h = self.child:bounds()
	gui.drawLine(x, y + b_h/2, x+10, y + (c_h/2))
	self.child:draw(x+10, y)
end

-------------
-- Decorators
-------------


BTNegate = class(BTDecorator, function(neg, name, child)
	BTDecorator.init(neg, "BTNegate", name, child)
end)

function BTNegate:decorate(tree, node, ctx)
	local ret = node:tick(tree, ctx)
	if ret == Success then
		return tree:failure(self)
	elseif ret == Failure then
		return tree:success(self)
	elseif ret:is_a(Running) then
		return tree:running(self,function(tree, ctx) return self:decorate(tree, node, ctx) end)
	else
		return tree:returned(self, ret)
	end
end

BTUntilFailure = class(BTDecorator, function(neg, name, child)
	BTDecorator.init(neg, "BTUntilFailure", name, child)
end)

function BTUntilFailure:decorate(tree, node, ctx)
	local ret = node:tick(tree, ctx)
	if ret == Failure then
		return tree:failure(self)
	elseif not is_a(ret,Invalid) then
		return tree:running(self, function(tree, ctx) return self:decorate(tree, node, ctx) end)
	else
		return tree:returned(self, ret)
	end
end

BTUntilSuccess = class(BTDecorator, function(neg, name, child)
	BTDecorator.init(neg, "BTUntilSuccess", name, child)
end)

function BTUntilSuccess:decorate(tree, node, ctx)
	local ret = node:tick(tree, ctx)
	if ret == Success then
		return tree:success(self)
	elseif is_a(ret,Invalid) == false then
		return tree:running(self, function(tree, ctx) return self:decorate(tree, node, ctx) end)
	else
		return tree:returned(self, ret)
	end
end

BTForever = class(BTDecorator, function(neg, name, child)
	BTDecorator.init(neg, "BTForever", name, child)
end)

function BTForever:decorate(tree, node, ctx)
	local ret = node:tick(tree, ctx)
	if ret:is_a(Invalid) then
		return tree:returned(self, ret)
	else
		return tree:running(function(tree, ctx) return self:decorate(tree, node, ctx) end)
	end
end

BTDecision = class(BTNode, function(act, type, name, test, params)
	BTNode.init(act, type, name)
	act.params = params or {}
	act.test = test
end)

function BTDecision:tick(tree, ctx)
	return tree:returned(self, self.test(tree, ctx, unpack(self.params)))
end


BTAction = class(BTNode, function(act, type, name, action, params)
	BTNode.init(act, type, name)
	act.params = params or {}
	act.action = action
end)

function BTAction:tick(tree, ctx)
	return self.action(tree, ctx, unpack(self.params))
end

-----------------
-- Parallel nodes
-----------------

BTParallelSimpleImmediate = class(BTNode, function(par, name, children)
	BTNode.init(par, "BTParallelSimpleImmediate", name)
	par.children = children
	par.running = {}
end)

function BTParallelSimpleImmediate:tick_state(tree, ctx, running)
	for i,child in ipairs(self.children) do
		local ret = (running[i] or child):tick(tree, pp)
		if (i == 1) and not is_a(ret, Running) then
			return tree:returned(self, ret)
		end
		if is_a(ret, Running) then
			running[i] = ret
		end
	end
	return tree:running(function(tree, ctx) self:tick_state(tree, ctx, running)end)
end

function BTParallelSimpleImmediate:tick(tree, ctx)
	return self:tick_state(tree, ctx, {})
end

BTParallelSimpleDelayed = class(BTNode, function(par, name, children)
	BTNode.init(par, "BTParallelSimpleDelayed", name)
	par.children = children
	par.running = {}
end)

function BTParallelSimpleDelayed:tick_state(tree, ctx, running)
	local can_finish = false
	for i,child in ipairs(self.children) do
		local ret = (running[i] or child):tick(tree, pp)
		if (i == 1) and not is_a(ret, Running) then
			can_finish = true
		end
		if is_a(ret, Running) then
			running[i] = ret
			can_finish = false
		else
			running[i] = nil
		end
	end
	if can_finish then
		return tree:success(self)
	else
		return tree:running(self, function(tree, ctx) self:tick_state(tree, ctx, running) end)
	end
end

function BTParallelSimpleDelayed:tick(tree, ctx)
	return self:tick_state(tree, ctx, {})
end


------------------------------
-- Blackboard set/check/remove
------------------------------

BTSetFact = class(BTNode, function(n, name, fact, value)
	BTNode.init(n, "BTSetFact", name)
	n.fact = fact
	n.value = value
end)

function BTSetFact:tick(tree, ctx)
	ctx:set_fact(self.fact, self.value)
	return tree:success(self)
end

BTCompareFact = class(BTNode, function(n, name, fact, value)
	BTNode.init(n, "BTCompareFact", name)
	n.fact = fact
	n.value = value
end)

function BTCompareFact:tick(tree, ctx)
	return tree:returned(self, ctx:get_fact(self.fact) == self.value)
end

BTCompareFactNot = class(BTNode, function(n, name, fact, value)
	BTNode.init(n, "BTCompareFactNot", name)
	n.fact = fact
	n.value = value
end)

function BTCompareFactNot:tick(tree, ctx)
	return tree:returned(self, ctx:get_fact(self.fact) ~= self.value)
end

BTCompareFactWithFact = class(BTNode, function(n, name, fact, other)
	BTNode.init(n, "BTCompareFactWithFact", name)
	n.fact = fact
	n.other = other
end)

function BTCompareFactWithFact:tick(tree, ctx)
	return tree:returned(self, ctx:get_fact(self.fact) == ctx:get_fact(self.other))
end

BTCompareFactWithFactNot = class(BTNode, function(n, name, fact, other)
	BTNode.init(n, "BTCompareFactWithFactNot", name)
	n.fact = fact
	n.other = other
end)

function BTCompareFactWithFactNot:tick(tree, ctx)
	return tree:returned(self, ctx:get_fact(self.fact) ~= ctx:get_fact(self.other))
end

BTHasFact = class(BTNode, function(n, name, fact)
	BTNode.init(n, "BTHasFact", name)
	n.fact = fact
end)

function BTHasFact:tick(tree, ctx)
	return tree:returned(self, ctx:has_fact(self.fact))
end

BTRemoveFact = class(BTNode, function(n, name, fact)
	BTNode.init(n, "BTRemoveFact", name)
	n.fact = fact
end)

function BTRemoveFact:tick(tree, ctx)
	ctx:remove_fact(self.fact)
	return tree:success(self)
end

------------------
-- BehaviorTree --
------------------

BehaviorTree = class(function(bt, tree)
	bt.tree = tree
	bt.tree_state = {}
	bt.state = Failure
end)

function BehaviorTree:tick(ctx)
	if (self.state == Success) or (self.state == Failure) then
		if self.tree ~= nil then
			self.tree_state = {}
			self.state = self.tree:tick(self, ctx)
		end
	elseif self.state:is_a(Running) then
		self.state = self.state:tick(self, ctx)
	end
end

function BehaviorTree:returned(node, val)
	if val == Success then
		self.tree_state[node] = "success"
	elseif val == Failure then
		self.tree_state[node] = "failure"
	elseif is_a(val, Running) then
		self.tree_state[node] = "running"
	else
		self.tree_state[node] = "invalid"
	end
	return val
end

function BehaviorTree:success(node)
	return self:returned(node, Success)
end

function BehaviorTree:failure(node)
	return self:returned(node, Failure)
end

function BehaviorTree:running(node, cb)
	return self:returned(node, Running(cb))
end

function BehaviorTree:invalid(node, msg)
	return self:returned(node, Invalid(msg))
end

function BehaviorTree:draw(x, y)
	if self.tree ~= nil then
		self.tree:draw(x, y)
		if is_a(self.state, Invalid) then
			
		else

		end
	else
		gui.drawText(x, y, "No tree set up!", 0xffff0000, 0xff000000)
	end
end
