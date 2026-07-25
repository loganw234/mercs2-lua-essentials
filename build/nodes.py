#!/usr/bin/env python3
"""build/nodes.py -- generate visual-editor node definitions from ess.json + a hand-curated overlay.

    dist/ess.json          (generated from src/ -- what functions EXIST, with real signatures)
  + api/nodes.overlay.json (hand-curated -- what a BEGINNER needs to know to use them)
  --------------------------------------------------------------------------------------
  = dist/nodes.json               the node contract, data only
  + dist/ess-nodes.generated.js   a ready-to-load consumer of it, proving the data is sufficient

WHY AN OVERLAY INSTEAD OF EDITING ess.json
ess.json is regenerated from src/ on every build, so anything hand-written into it would be destroyed by the
next `python build/manifest.py`. The overlay is the committed, human-authored half; this script merges them.
Same split the rest of this repo already uses: derived things live in dist/ and are rebuilt, captured/authored
things live in api/ and are committed.

THE OVERLAY CANNOT INVENT ANYTHING. Every entry is checked against ess.json: an overlay key naming a function
that doesn't exist, or a param that isn't in the real signature, fails the build (`--check`). The overlay adds
MEANING to a real signature; it can never add a signature. That's what keeps a hand-maintained file from
drifting into fiction -- the exact failure mode this repo's manifest work was about in the first place.

TYPE VOCABULARY, and how each one reaches the generated Lua:
  number    a numeric widget, spliced RAW              ->  Ess.Object.setYaw(g, 90)
  string    a text widget, QUOTED via CodeGen.luaString ->  Ess.Object.spawn('Veyron', ...)
  guid      a text widget holding a Lua EXPRESSION, spliced raw. NOT a quoted string -- a guid is a live
            engine handle, so the widget's text is code: `Ess.Player.character(0)`, or a wire from a
            capturing node. This is the single most important distinction in the whole file; getting it
            wrong produces Lua that quotes a handle and silently does nothing.
  bool      a toggle, spliced raw as true/false
  table     a text widget holding a Lua table literal, spliced raw   ->  { x, y, z }
  function  a text widget holding a Lua function expression, spliced raw
  lua       any other raw Lua expression

KIND:
  action    has exec pins (in at slot 0, out at slot 0). Emits a STATEMENT. If it returns values they are
            captured into locals and exposed as data outputs.
  getter    no exec pins at all. Emits the call EXPRESSION straight into its output slot, evaluated wherever
            it is spliced. Only for side-effect-free reads.

NODE TYPE IDS are prefixed `essgen/` deliberately, NOT `ess/`. The visual editor has ~200 hand-written `ess/`
nodes; registering generated types under the same ids would silently overwrite hand-tuned ones depending on
script load order. `essgen/` lets both coexist so the editor can migrate deliberately, one namespace at a
time, rather than all at once by accident.

Usage:
  python build/nodes.py            # write dist/nodes.json + dist/ess-nodes.generated.js
  python build/nodes.py --check    # validate the overlay against ess.json; exit 1 on any problem
  python build/nodes.py --report   # coverage: what's covered, skipped, and still unenriched
"""
import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
API = ROOT / "api"
OVERLAY = API / "nodes.overlay.json"

VALID_TYPES = {"number", "string", "guid", "bool", "table", "function", "lua"}

# What to construct for a method-style function's receiver when the overlay doesn't name one. These are the
# three namespaces in Ess defined with `:` methods, and each has an obvious constructor.
RECEIVER_DEFAULTS = {
    "Ess.RNG": "Ess.RNG.new()",
    "Ess.Track": "Ess.Track.new()",
    "Ess.SaveVar": "Ess.SaveVar.ns('MyMod')",
}
VALID_KINDS = {"action", "getter"}

# ---------------------------------------------------------------------------------------------------------
# Type inference from parameter names. This is a STARTING POINT, not the answer -- the overlay overrides it,
# and the fine pass exists because the same name genuinely means different things in different namespaces
# (`i` is a player index in Ess.Player but an array index in Ess.Table; `t` is an options table in some
# namespaces and a plain array in Ess.Table). Anything inferred and not confirmed by the overlay is reported
# by --report as unenriched rather than quietly trusted.
# ---------------------------------------------------------------------------------------------------------
GUID_NAMES = {"uGuid", "uChar", "uVeh", "uHeli", "uAnchor", "uFx", "uSource", "uWeapon", "uObj", "uTarget",
              "guid", "char", "veh", "target", "fromGuid", "uGuidA", "uGuidB", "vehGuid", "targetGuid"}
FUNC_PREFIXES = ("fn", "cb", "on", "callback")
TABLE_NAMES = {"opts", "tOpts", "spec", "steps", "guids", "points", "list", "defaults", "entries", "pairsList",
               "factionList", "spawns", "objectives", "def", "t", "tHandles", "tGuids", "args", "at"}
STRING_NAMES = {"name", "sName", "label", "sLabel", "text", "msg", "sMsg", "key", "id", "sId", "teamName",
                "sTemplate", "template", "s", "sep", "title", "sTitle", "desc", "sDesc", "behavior", "cue",
                "faction", "sFaction", "action", "sActionName", "role", "kind", "sHash", "prefix", "ns"}


def infer_type(param, namespace):
    p = param
    if p in GUID_NAMES:
        return "guid"
    if p.startswith("u") and len(p) > 1 and p[1].isupper():
        return "guid"
    if p.startswith(FUNC_PREFIXES) and (p == "fn" or p[:2] == "on" or p.startswith("cb")):
        return "function"
    if p.startswith("b") and len(p) > 1 and p[1].isupper():
        return "bool"
    if p.startswith("s") and len(p) > 1 and p[1].isupper():
        return "string"
    if p.startswith("n") and len(p) > 1 and p[1].isupper():
        return "number"
    if p.startswith("t") and len(p) > 1 and p[1].isupper():
        return "table"
    if p in STRING_NAMES:
        return "string"
    if p in TABLE_NAMES:
        # `t` in Ess.Table is the collection being operated on; elsewhere it tends to be an options table.
        return "table"
    if p in {"x", "y", "z", "x1", "y1", "z1", "x2", "y2", "z2", "r", "radius", "n", "i", "j", "yaw", "dist",
             "amount", "seconds", "interval", "strength", "pct", "v", "lo", "hi", "count", "slot", "level",
             "index", "delay", "duration", "speed", "alpha", "size", "height", "width"}:
        return "number"
    return "lua"


def short_desc(text, limit=110):
    """First sentence of a description, for a tooltip or a palette row.

    The full descriptions are deliberately long -- they carry the engine traps that are the entire reason this
    framework exists (a helicopter running combat AI ignores a land order; a pursuit cap is one-way for the
    session). That belongs in a details pane, but it is far too much for a hover. Rather than make the fine
    pass write everything twice, the first sentence is split out here and BOTH are shipped: `desc_short` for
    the tooltip, `desc` for the panel. Nothing is lost either way.
    """
    if not text:
        return ""
    text = " ".join(text.split())
    m = re.match(r"(.{20,%d}?[.!?])(\s|$)" % limit, text)
    if m:
        return m.group(1)
    if len(text) <= limit:
        return text
    cut = text[:limit].rsplit(" ", 1)[0]
    return cut + "..."


def title_of(call):
    """Ess.Object.spawnAhead -> 'Object: Spawn Ahead'  (namespace prefix keeps the palette scannable)."""
    parts = call.split(".")
    fn = parts[-1]
    ns = ".".join(parts[1:-1]) or "Ess"
    words = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", " ", fn)
    return "%s: %s" % (ns.replace("Easy.", "Easy "), words[0].upper() + words[1:])


def node_id(call):
    return "essgen/" + "/".join(p.lower() for p in call.split(".")[1:])


def load():
    ess_path = DIST / "ess.json"
    if not ess_path.exists():
        print("[nodes] dist/ess.json missing -- run `python build/manifest.py` first")
        sys.exit(1)
    ess = json.loads(ess_path.read_text(encoding="utf-8"))
    overlay = json.loads(OVERLAY.read_text(encoding="utf-8")) if OVERLAY.exists() else {"functions": {}}
    return ess, overlay


def validate_overlay(ess, overlay):
    """The overlay may only DESCRIBE what ess.json says exists. Returns a list of problems."""
    problems = []
    real = ess["functions"]
    for call, entry in sorted(overlay.get("functions", {}).items()):
        if call not in real:
            problems.append("overlay describes %s, which is not in ess.json" % call)
            continue
        real_params = set(real[call]["params"])
        for pname in entry.get("params", {}):
            if pname not in real_params:
                problems.append("overlay gives %s a param %r, whose real signature is (%s)"
                                % (call, pname, ", ".join(real[call]["params"]) or "no params"))
        kind = entry.get("kind")
        if kind is not None and kind not in VALID_KINDS:
            problems.append("%s has kind %r (expected one of %s)" % (call, kind, sorted(VALID_KINDS)))
        for pname, p in entry.get("params", {}).items():
            t = p.get("type")
            if t is not None and t not in VALID_TYPES:
                problems.append("%s param %s has type %r (expected one of %s)"
                                % (call, pname, t, sorted(VALID_TYPES)))
        for r in entry.get("returns", []) or []:
            if r.get("type") not in VALID_TYPES:
                problems.append("%s return %r has type %r" % (call, r.get("name"), r.get("type")))

    # THE MULTI-RETURN SPILL. Lua truncates a multi-value call to ONE value only when it is NOT the last item
    # in an argument list -- so a default of `Ess.Player.targetUnderReticle(0)`, which returns (guid, x, y, z),
    # quietly spills three extra arguments into the following parameters of whatever call it lands in. It has
    # to be written `(Ess.Player.targetUnderReticle(0))` to truncate to the guid.
    #
    # A bare call inside a TABLE constructor is fine and often intended -- `{ Ess.Player.pose(0) }` builds
    # {x, y, z, yaw, char, player} on purpose -- so that shape is allowed.
    multi = {c for c, e in overlay.get("functions", {}).items() if len((e.get("returns") or [])) > 1}
    for call, entry in sorted(overlay.get("functions", {}).items()):
        for pname, p in (entry.get("params") or {}).items():
            dflt = str(p.get("default", "") or "").strip()
            if not dflt or dflt.startswith("(") or dflt.startswith("{"):
                continue
            for m in multi:
                if m + "(" in dflt:
                    problems.append(
                        "%s param %s defaults to a bare %s(...), which returns %d values and would spill the "
                        "extras into the next argument -- wrap it in parentheses to truncate it"
                        % (call, pname, m, len(overlay["functions"][m]["returns"])))
    return problems


def build_nodes(ess, overlay):
    real = ess["functions"]
    ov = overlay.get("functions", {})
    skip_ns = set(overlay.get("skip_namespaces", []))
    nodes, skipped, unenriched = [], [], []

    for call in sorted(real):
        e = real[call]
        entry = ov.get(call, {})
        if entry.get("skip") or e["namespace"] in skip_ns:
            skipped.append({"call": call, "reason": entry.get("skip_reason")
                            or ("namespace %s is excluded" % e["namespace"])})
            continue

        # METHOD-STYLE FUNCTIONS need a receiver, or the generated Lua is silently wrong.
        # `function Ess.RNG:int(n)` desugars to `Ess.RNG.int(self, n)`, so emitting `Ess.RNG.int(5)` passes 5
        # as SELF and leaves n nil -- no error, just a wrong answer. There are 21 of these (Ess.Track's
        # tracker methods, Ess.RNG's draws, Ess.SaveVar's namespace accessors), and they are exactly the ones
        # a graph most wants. So a synthetic leading "receiver" input is prepended, defaulting to a call that
        # constructs one, and the emitter uses `receiver:method(args)` instead of a dotted call.
        params = []
        if e.get("method"):
            ns = call.rsplit(".", 1)[0]
            recv = (entry.get("receiver") or {})
            params.append({
                "name": recv.get("name", "instance"),
                "type": recv.get("type", "lua"),
                "default": recv.get("default", RECEIVER_DEFAULTS.get(ns, ns + ".new()")),
                "desc": recv.get("desc") or ("The %s to call this on. The default builds a fresh one inline, "
                                             "which works but makes a new one every call -- wire in a shared "
                                             "one if you need the same instance across nodes." % ns),
                "optional": False,
                # Not "inferred" when the namespace has a known constructor: the receiver's type is `lua` by
                # definition (an opaque instance handle), and the default is that namespace's own documented
                # constructor -- neither is a guess from a parameter name, which is what `inferred` means
                # everywhere else in this file. Only an unknown namespace falling back to "<Ns>.new()" is.
                "inferred": "receiver" not in entry and ns not in RECEIVER_DEFAULTS,
                "receiver": True,
            })
        for pname in e["params"]:
            po = (entry.get("params") or {}).get(pname, {})
            params.append({
                "name": pname,
                "type": po.get("type") or infer_type(pname, e["namespace"]),
                "default": po.get("default", None),
                "desc": po.get("desc", ""),
                "optional": po.get("optional", False),
                "inferred": "type" not in po,
            })

        returns = entry.get("returns", []) or []
        kind = entry.get("kind", "action")
        promoted = None
        # A GETTER emits its call spliced inline as an expression -- and Lua truncates a multi-value call to
        # ONE value unless it is the last item in a list, so a pure-data getter physically cannot deliver a
        # second output. (The editor's own convention was to SKIP such functions for exactly this reason.)
        # Promoting to an action instead captures into real locals -- `local x, y, z = Ess.Object.pos(g)` --
        # which delivers every value AND keeps the function available, rather than dropping it.
        if kind == "getter" and len(returns) > 1:
            kind, promoted = "action", "multi-value return cannot be spliced inline as an expression"

        node = {
            "id": node_id(call),
            "call": call,
            "title": entry.get("title") or title_of(call),
            "desc": entry.get("desc") or e.get("description", ""),
            "desc_short": short_desc(entry.get("desc") or e.get("description", "")),
            "category": entry.get("category") or e["namespace"],
            "tier": e["tier"],
            "kind": kind,
            "params": params,
            "returns": returns,
            "source": {"file": e["file"], "line": e["line"]},
            "enriched": bool(entry),
        }
        if e.get("method"):
            node["method"] = True
            node["method_name"] = call.rsplit(".", 1)[1]
        if promoted:
            node["promoted_from_getter"] = promoted
        if not entry:
            unenriched.append(call)
        nodes.append(node)

    return nodes, skipped, unenriched


JS_HEADER = '''/* ess-nodes.generated.js -- GENERATED by build/nodes.py in mercs2-lua-essentials. DO NOT EDIT BY HAND.
 *
 * Registers a litegraph node type for every Ess function in dist/nodes.json. Load it AFTER litegraph.js and
 * after the editor's own codegen.js -- it uses CodeGen for emission and nothing else.
 *
 * TYPE IDS ARE PREFIXED `essgen/`, never `ess/`. The editor's hand-written nodes own the `ess/` prefix; using
 * it here would silently overwrite hand-tuned nodes depending on script load order. Both can coexist, so a
 * migration can happen one namespace at a time on purpose rather than all at once by accident.
 *
 * The one compatibility shim below is deliberate: the editor's input resolver has been called both
 * `resolveInput` and `resolveNumberInput`. Binding whichever exists means this file keeps working across that
 * rename instead of breaking on it.
 */
(function () {
  "use strict";
  if (typeof LiteGraph === "undefined" || typeof CodeGen === "undefined") {
    (typeof console !== "undefined") && console.warn("[essgen] LiteGraph/CodeGen not loaded -- skipping");
    return;
  }
  var resolve = CodeGen.resolveInput || CodeGen.resolveNumberInput;

  // Turn one param's widget/wire value into a fragment of Lua SOURCE. The `guid`/`table`/`function`/`lua`
  // cases splice RAW because their widget text already IS code -- quoting a guid produces Lua that silently
  // does nothing, which is the single easiest mistake to make here.
  function luaArg(type, value) {
    if (value === undefined || value === null || value === "") return "nil";
    if (type === "string") return CodeGen.luaString(String(value));
    if (type === "bool") return (value === true || value === "true") ? "true" : "false";
    return String(value);   // number / guid / table / function / lua -- already Lua source
  }

  function widgetFor(type) {
    if (type === "number") return "number";
    if (type === "bool") return "toggle";
    return "text";
  }

  function makeNode(def) {
    function Node() {
      var self = this;
      if (def.kind === "action") {
        this.addInput("exec", LiteGraph.ACTION);      // ALWAYS slot 0 -- value inputs start at 1
        this.addOutput("then", LiteGraph.EVENT);
      }
      def.params.forEach(function (p) {
        var dflt = p.default === undefined || p.default === null ? defaultFor(p.type) : p.default;
        self.addInput(p.name, p.type === "number" ? "number" : "string");
        self.addProperty(p.name, dflt);
        self.addWidget(widgetFor(p.type), p.name, dflt, function (v) { self.properties[p.name] = v; });
      });
      (def.returns || []).forEach(function (r) {
        self.addOutput(r.name, r.type === "number" ? "number" : "string");
      });
      if (def.params.length > 3) this.size = [260, 30 + 24 * def.params.length];
    }
    Node.title = def.title;
    Node.desc = def.desc || def.call;
    Node.prototype.essDef = def;

    function resolved(node) {
      var base = def.kind === "action" ? 1 : 0;   // slot 0 is "exec" on an action node
      return def.params.map(function (p, idx) {
        var wired = resolve ? resolve(node, base + idx, p.name) : node.properties[p.name];
        return luaArg(p.type, wired);
      });
    }

    // METHOD-STYLE functions must be emitted as `receiver:name(rest)`. A dotted `Ess.RNG.int(5)` would pass
    // 5 as SELF and leave the real argument nil -- no error, just a wrong answer, which is the worst kind.
    function callText(node) {
      var vals = resolved(node);
      if (def.method) {
        var recv = vals.shift();
        return recv + ":" + def.method_name + "(" + vals.join(", ") + ")";
      }
      return def.call + "(" + vals.join(", ") + ")";
    }

    if (def.kind === "action") {
      Node.prototype.onAction = function () {
        var call = callText(this);
        var rets = def.returns || [];
        if (rets.length === 0) {
          CodeGen.emit(call);
        } else {
          // Multi-value returns get one local each, so a function like Ess.Player.pose can expose x, y and z
          // as three separate wireable outputs instead of being skipped for having no single primary value.
          var names = rets.map(function (r) { return CodeGen.newLocal(r.name); });
          CodeGen.emit("local " + names.join(", ") + " = " + call);
          var slot = 1;   // output 0 is "then"
          names.forEach(function (n) { this.setOutputData(slot++, n); }, this);
        }
        this.triggerSlot(0);
      };
    } else {
      Node.prototype.onExecute = function () {
        this.setOutputData(0, "(" + callText(this) + ")");
      };
    }
    LiteGraph.registerNodeType(def.id, Node);
  }

  function defaultFor(type) {
    if (type === "number") return 0;
    if (type === "bool") return false;
    if (type === "guid") return "Ess.Player.character(0)";
    if (type === "table") return "{}";
    if (type === "function") return "function() end";
    return "";
  }

  var DEFS = /*__NODES__*/[]/*__END__*/;
  DEFS.forEach(makeNode);
  if (typeof console !== "undefined") {
    console.log("[essgen] registered " + DEFS.length + " generated Ess nodes");
  }
})();
'''


def main():
    ap = argparse.ArgumentParser(description="Generate visual-editor node definitions from ess.json.")
    ap.add_argument("--check", action="store_true", help="validate the overlay against ess.json; exit 1 on drift")
    ap.add_argument("--report", action="store_true", help="print coverage: covered / skipped / unenriched")
    args = ap.parse_args()

    ess, overlay = load()
    problems = validate_overlay(ess, overlay)

    if args.check:
        if problems:
            print("[nodes] OVERLAY DRIFT -- %d problem(s):" % len(problems))
            for p in problems:
                print("  - " + p)
            sys.exit(1)
        print("[nodes] overlay clean: every entry matches a real function and signature.")
        return

    if problems:
        print("[nodes] refusing to generate -- %d overlay problem(s). Run --check for the list." % len(problems))
        sys.exit(1)

    nodes, skipped, unenriched = build_nodes(ess, overlay)

    if args.report:
        by_cat = {}
        for n in nodes:
            by_cat.setdefault(n["category"], []).append(n)
        print("[nodes] %d nodes, %d skipped, %d unenriched" % (len(nodes), len(skipped), len(unenriched)))
        print("[nodes] enriched: %d/%d (%d%%)"
              % (len(nodes) - len(unenriched), len(nodes),
                 100 * (len(nodes) - len(unenriched)) // max(len(nodes), 1)))
        inferred = sum(1 for n in nodes for p in n["params"] if p["inferred"])
        total_p = sum(len(n["params"]) for n in nodes)
        print("[nodes] params with a CONFIRMED type: %d/%d (%d%%)"
              % (total_p - inferred, total_p, 100 * (total_p - inferred) // max(total_p, 1)))
        print("\nleast-enriched categories:")
        for cat, ns in sorted(by_cat.items(), key=lambda kv: -sum(1 for n in kv[1] if not n["enriched"]))[:12]:
            miss = sum(1 for n in ns if not n["enriched"])
            if miss:
                print("  %-26s %d/%d unenriched" % (cat, miss, len(ns)))
        return

    DIST.mkdir(exist_ok=True)
    payload = {
        "_comment": "Generated by build/nodes.py from dist/ess.json + api/nodes.overlay.json. Do not hand-edit; "
                    "edit the overlay instead. Node type ids are prefixed essgen/ so they cannot collide with "
                    "the visual editor's own hand-written ess/ nodes.",
        "version": ess["version"],
        "generated": ess["generated"],
        "counts": {"nodes": len(nodes), "skipped": len(skipped), "unenriched": len(unenriched)},
        "nodes": nodes,
        "skipped": skipped,
    }
    (DIST / "nodes.json").write_text(json.dumps(payload, indent=1) + "\n", encoding="utf-8")

    js = JS_HEADER.replace("/*__NODES__*/[]/*__END__*/", json.dumps(nodes, indent=1))
    (DIST / "ess-nodes.generated.js").write_text(js, encoding="utf-8")

    print("[nodes] wrote %s  (%d nodes, %d skipped)" % (DIST / "nodes.json", len(nodes), len(skipped)))
    print("[nodes] wrote %s" % (DIST / "ess-nodes.generated.js"))
    print("[nodes] enriched %d/%d; run --report for the gaps" % (len(nodes) - len(unenriched), len(nodes)))


if __name__ == "__main__":
    main()
