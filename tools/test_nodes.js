/* tools/test_nodes.js -- execute dist/ess-nodes.generated.js against a stubbed editor and assert the LUA it
 * produces. Run: `node tools/test_nodes.js` (no browser, no editor repo, no game).
 *
 * A `node --check` only proves the file parses. This proves the nodes actually WORK: that they register, that
 * their inputs land in the right slots, and above all that each parameter type reaches the generated Lua in
 * the right shape. That last one is the whole ballgame -- a `guid` spliced as a quoted string produces Lua
 * that runs, logs nothing, and silently does nothing, which is precisely the failure mode Ess.DEBUG exists to
 * fight. It has to be caught here, not by a confused beginner.
 *
 * The LiteGraph/CodeGen stubs below mirror the real editor's contract as read from its source: "exec" is
 * always input slot 0 on an action node, value inputs follow it, a wired input beats the widget default, and
 * CodeGen.luaString single-quotes. If the editor ever changes that contract, this harness is where the
 * mismatch should surface.
 */
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const ROOT = path.resolve(__dirname, "..");
const GENERATED = path.join(ROOT, "dist", "ess-nodes.generated.js");
const NODES_JSON = path.join(ROOT, "dist", "nodes.json");

let failures = 0;
function check(label, cond, detail) {
  if (!cond) { failures++; console.log("  [FAIL] " + label + (detail ? "  -- " + detail : "")); }
}

// ---- stubs -------------------------------------------------------------------------------------------
const registered = new Map();
const emitted = [];
let localCounter = 0;

const LiteGraph = {
  ACTION: "@ACTION",
  EVENT: "@EVENT",
  registerNodeType(id, ctor) { registered.set(id, ctor); },
};

const CodeGen = {
  emit(line) { emitted.push(line); },
  luaString(s) { return "'" + String(s).replace(/\\/g, "\\\\").replace(/'/g, "\\'") + "'"; },
  newLocal(prefix) { localCounter += 1; return "__" + (prefix || "v") + localCounter; },
  // The editor renamed this helper at least once (resolveNumberInput -> resolveInput); the generated file
  // binds whichever exists, so the stub provides the current name only, deliberately -- if the generated
  // file ever stops handling the rename, this harness fails instead of the browser.
  resolveInput(node, slot, prop) {
    const wired = node.__wired[slot];
    return wired !== undefined ? wired : node.properties[prop];
  },
};

// Minimal node instance: enough surface for the generated constructors and handlers.
// Built on the constructor's PROTOTYPE (litegraph does `new Ctor()`), because onAction/onExecute live there --
// a plain object with ctor.call() gets the fields but none of the handlers, which is how the first run of this
// harness "failed" every node for a reason that was entirely the harness's own fault.
function instantiate(ctor) {
  const node = Object.assign(Object.create(ctor.prototype), {
    inputs: [], outputs: [], properties: {}, widgets: [], __wired: {}, __out: {}, size: null,
    addInput(name, type) { this.inputs.push({ name, type }); },
    addOutput(name, type) { this.outputs.push({ name, type }); },
    addProperty(name, value) { this.properties[name] = value; },
    addWidget(kind, name, value, cb) { this.widgets.push({ kind, name, value, cb }); },
    setOutputData(slot, data) { this.__out[slot] = data; },
    getInputData(slot) { return this.__wired[slot]; },
    triggerSlot() { this.__triggered = true; },
  });
  ctor.call(node);
  return node;
}

// ---- load --------------------------------------------------------------------------------------------
if (!fs.existsSync(GENERATED)) {
  console.log("[nodes-test] " + GENERATED + " missing -- run `python build/nodes.py` first");
  process.exit(2);
}
const sandbox = { LiteGraph, CodeGen, console: { log() {}, warn() {} } };
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(GENERATED, "utf8"), sandbox, { filename: "ess-nodes.generated.js" });

const defs = JSON.parse(fs.readFileSync(NODES_JSON, "utf8")).nodes;
console.log("[nodes-test] " + registered.size + " node types registered from " + defs.length + " definitions");
check("every definition registered a node type", registered.size === defs.length,
      registered.size + " != " + defs.length);

// ---- structural invariants over EVERY node -----------------------------------------------------------
const ids = new Set();
let actions = 0, getters = 0, emitProblems = [];
for (const def of defs) {
  check("id is unique: " + def.id, !ids.has(def.id));
  ids.add(def.id);
  check("id is namespaced essgen/ (cannot collide with the editor's own ess/ nodes): " + def.id,
        def.id.startsWith("essgen/"));
  check("has a title: " + def.id, !!def.title);

  const ctor = registered.get(def.id);
  check("registered: " + def.id, !!ctor);
  if (!ctor) continue;

  const node = instantiate(ctor);
  if (def.kind === "action") {
    actions++;
    check("action node's slot 0 is exec: " + def.id,
          node.inputs[0] && node.inputs[0].type === LiteGraph.ACTION,
          JSON.stringify(node.inputs[0]));
    check("action node's output 0 is the exec chain: " + def.id,
          node.outputs[0] && node.outputs[0].type === LiteGraph.EVENT);
    check("value inputs follow exec: " + def.id,
          node.inputs.length === def.params.length + 1);
  } else {
    getters++;
    check("getter has NO exec input: " + def.id,
          !node.inputs.some((i) => i.type === LiteGraph.ACTION));
    check("getter returns exactly one value (multi-value must be promoted to an action): " + def.id,
          (def.returns || []).length <= 1, JSON.stringify(def.returns));
  }

  // Every param must get a widget so it is editable without wiring anything.
  check("every param has a widget: " + def.id, node.widgets.length === def.params.length);

  // Exercise the emitter with defaults and confirm it produces a plausible Lua call.
  emitted.length = 0;
  try {
    if (def.kind === "action") { node.onAction(); } else { node.onExecute(); }
  } catch (e) {
    emitProblems.push(def.id + ": threw -- " + e.message);
    continue;
  }
  const lua = def.kind === "action" ? emitted.join("\n") : String(node.__out[0] || "");
  // A method-style node legitimately does NOT contain its dotted name: `Ess.RNG:chance` emits
  // `Ess.RNG.new():chance(0.5)`. Look for the colon form there instead of failing correct output.
  const wanted = def.method ? ":" + def.method_name + "(" : def.call;
  if (!lua.includes(wanted)) emitProblems.push(def.id + ": emitted Lua missing " + wanted + " -- " + lua);
  const opens = (lua.match(/\(/g) || []).length, closes = (lua.match(/\)/g) || []).length;
  if (opens !== closes) emitProblems.push(def.id + ": unbalanced parens -- " + lua);
}
check("no node threw or emitted malformed Lua", emitProblems.length === 0,
      emitProblems.slice(0, 5).join(" | "));

// ---- the type contract, which is the part that silently breaks graphs --------------------------------
function emitFor(id, props, wires) {
  const ctor = registered.get(id);
  if (!ctor) return null;
  const node = instantiate(ctor);
  Object.assign(node.properties, props || {});
  Object.assign(node.__wired, wires || {});
  emitted.length = 0;
  const def = defs.find((d) => d.id === id);
  if (def.kind === "action") { node.onAction(); return emitted.join("\n"); }
  node.onExecute(); return String(node.__out[0] || "");
}

const stringParam = defs.find((d) => d.params.some((p) => p.type === "string"));
if (stringParam) {
  const p = stringParam.params.find((x) => x.type === "string");
  const lua = emitFor(stringParam.id, { [p.name]: "hello world" });
  check("a STRING param is quoted: " + stringParam.id, lua && lua.includes("'hello world'"), lua);
}

const guidParam = defs.find((d) => d.params.some((p) => p.type === "guid"));
if (guidParam) {
  const p = guidParam.params.find((x) => x.type === "guid");
  const lua = emitFor(guidParam.id, { [p.name]: "Ess.Player.character(0)" });
  check("a GUID param is spliced RAW, never quoted: " + guidParam.id,
        lua && lua.includes("Ess.Player.character(0)") && !lua.includes("'Ess.Player.character(0)'"), lua);
}

const boolParam = defs.find((d) => d.params.some((p) => p.type === "bool"));
if (boolParam) {
  const p = boolParam.params.find((x) => x.type === "bool");
  const lua = emitFor(boolParam.id, { [p.name]: true });
  check("a BOOL param emits a Lua boolean: " + boolParam.id, lua && /\btrue\b/.test(lua), lua);
}

const tableParam = defs.find((d) => d.params.some((p) => p.type === "table"));
if (tableParam) {
  const p = tableParam.params.find((x) => x.type === "table");
  const lua = emitFor(tableParam.id, { [p.name]: "{ 1, 2, 3 }" });
  check("a TABLE param is spliced RAW: " + tableParam.id,
        lua && lua.includes("{ 1, 2, 3 }") && !lua.includes("'{ 1, 2, 3 }'"), lua);
}

// A wired input must beat the widget default -- that is the entire point of having pins.
const wirable = defs.find((d) => d.kind === "action" && d.params.length > 0);
if (wirable) {
  const lua = emitFor(wirable.id, {}, { 1: "__spawn1" });
  check("a WIRED input overrides the widget default: " + wirable.id, lua && lua.includes("__spawn1"), lua);
}

// METHOD-STYLE functions must emit `receiver:name(args)`, never a dotted call. `function Ess.RNG:int(n)`
// desugars to `Ess.RNG.int(self, n)`, so a dotted `Ess.RNG.int(5)` passes 5 as SELF and leaves n nil -- it
// throws nothing and returns a wrong answer, which is exactly the class of silent failure this whole repo
// has been about. Caught originally by a source-reading pass, not by anything mechanical, so it gets a test.
const methodNodes = defs.filter((d) => d.method);
check("method-style functions exist in the manifest", methodNodes.length > 0);
for (const def of methodNodes) {
  const recv = def.params[0];
  check("method node's first param is its receiver: " + def.id, recv && recv.receiver === true,
        JSON.stringify(recv && recv.name));
  const lua = emitFor(def.id, {});
  check("method node emits receiver:name(...), not a dotted call: " + def.id,
        lua && lua.includes(":" + def.method_name + "(") && !lua.includes(def.call + "("), lua);
}

// Multi-value returns must capture into that many distinct locals.
const multi = defs.find((d) => (d.returns || []).length > 1);
if (multi) {
  const lua = emitFor(multi.id, {});
  const decl = (lua.match(/^local ([^=]+)=/m) || [])[1] || "";
  check("a multi-value return captures one local per value: " + multi.id,
        decl.split(",").length === multi.returns.length, lua);
}

console.log("[nodes-test] " + actions + " action nodes, " + getters + " getter nodes");
if (failures === 0) {
  console.log("[nodes-test] all checks passed");
  process.exit(0);
}
console.log("[nodes-test] " + failures + " check(s) FAILED");
process.exit(1);
