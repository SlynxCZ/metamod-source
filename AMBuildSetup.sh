#!/bin/bash
set -euo pipefail

# ---------------------- CONFIGURE BUILD ----------------------
echo "=== CONFIGURE ==="

NAME="core/metamod.2.cs2"
export NAME

echo "Name: $NAME"

mkdir -p build
cd build

python3 ../configure.py \
    --enable-optimize \
    --sdks cs2 \
    --hl2sdk-root="$HL2SDKCS2" \
    --generate-compile-commands \
    || { echo "CONFIGURE FAILED — STOPPING"; exit 20; }

# ---------------------- PROTO GEN ----------------------

echo "=== PROTO==="

PROTO_SRC_DIR1="$HL2SDKCS2/common"
PROTO_SRC_DIR2="$CSGO_PROTO_DIR"
PROTO_OUT_DIR="./$NAME/linux-x86_64"

mkdir -p "$PROTO_OUT_DIR"

echo "Protobuf output directory: $PROTO_OUT_DIR"
PROTOC="$HL2SDKCS2/devtools/bin/linux/protoc"

echo "Generating protobufs from: $PROTO_SRC_DIR1"
for PROTO in "$PROTO_SRC_DIR1"/*.proto; do
    [ -e "$PROTO" ] || continue
    "$PROTOC" \
        -I "$HL2SDKCS2/thirdparty/protobuf-3.21.8/src" \
        -I "$PROTO_SRC_DIR1" \
        --cpp_out="$PROTO_OUT_DIR" \
        "$PROTO"
done

echo ""
echo "Generating protobufs from: $PROTO_SRC_DIR2"
for PROTO in "$PROTO_SRC_DIR2"/*.proto; do
    [ -e "$PROTO" ] || continue
    "$PROTOC" \
        -I "$HL2SDKCS2/thirdparty/protobuf-3.21.8/src" \
        -I "$PROTO_SRC_DIR2" \
        --cpp_out="$PROTO_OUT_DIR" \
        "$PROTO"
done

# ---------------------- FIX COMPILE_COMMANDS ----------------------

echo "=== FIXING COMPILE_COMMANDS.JSON FOR CLION ==="

cd ..

SOURCE_JSON="./build/compile_commands.json"
TARGET_JSON="./compile_commands.json"

cp "$SOURCE_JSON" "$TARGET_JSON"

python3 - << 'EOF'
import json, os

FILE = "compile_commands.json"
project_root = os.getcwd()

# Pull from exported environment variables
PLUGIN_NAME = os.environ.get("NAME")

if not PLUGIN_NAME:
    raise RuntimeError("PLUGIN_NAME environment variable is missing!")

build_root = os.path.join(project_root, "build")
plugin_root = os.path.join(build_root, PLUGIN_NAME)
final_dir = os.path.abspath(os.path.join(plugin_root, "linux-x86_64"))

print("Project root :", project_root)
print("Plugin name  :", PLUGIN_NAME)
print("Final dir    :", final_dir)

# Load compile_commands.json
with open(FILE) as f:
    db = json.load(f)

fixed = []

for cmd in db:

    # -----------------------------------
    # FORCE directory to final build dir
    # -----------------------------------
    cmd["directory"] = final_dir

    # -----------------------------------
    # Make file absolute
    # -----------------------------------
    file = cmd.get("file", "")
    if file and not file.startswith("/"):
        cmd["file"] = os.path.abspath(os.path.join(final_dir, file))

    # -----------------------------------
    # Make output path absolute
    # -----------------------------------
    out = cmd.get("output", "")
    if out and not out.startswith("/"):
        cmd["output"] = os.path.abspath(os.path.join(final_dir, out))

    # -----------------------------------
    # Fix includes + source paths
    # -----------------------------------
    new_args = []
    args = cmd.get("arguments", [])
    skip = False

    for i in range(len(args)):
        if skip:
            skip = False
            continue

        # Case: "-I", "relative/path"
        if args[i] == "-I" and i + 1 < len(args):
            inc = args[i+1]
            if not inc.startswith("/"):
                inc = os.path.abspath(os.path.join(final_dir, inc))
            new_args.append("-I" + inc)
            skip = True
            continue

        # Case: "-Irelative"
        if args[i].startswith("-I") and not args[i][2:].startswith("/"):
            rel = args[i][2:]
            abs_inc = os.path.abspath(os.path.join(final_dir, rel))
            new_args.append("-I" + abs_inc)
            continue

        # Fix source files in arguments
        if (args[i].endswith(".c") or args[i].endswith(".cc") or args[i].endswith(".cpp")) and not args[i].startswith("/"):
            new_args.append(os.path.abspath(os.path.join(final_dir, args[i])))
            continue

        new_args.append(args[i])

    cmd["arguments"] = new_args
    fixed.append(cmd)

# Write back
with open(FILE, "w") as f:
    json.dump(fixed, f, indent=2)

print("compile_commands.json fully normalized.")
EOF

echo "=== DONE ==="
