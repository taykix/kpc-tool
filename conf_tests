#!/bin/bash

SCRIPT_ROOT_DIR="$(pwd)"
LINUX_DIR_NAME="linux"
LINUX_DIR_PATH="$SCRIPT_ROOT_DIR/$LINUX_DIR_NAME"
CONF_TOOLS_DIR="$SCRIPT_ROOT_DIR/conf_tools"
TEST_RESULTS_DIR="$SCRIPT_ROOT_DIR/test_results"
MAIN_CSV_REPORT="$SCRIPT_ROOT_DIR/backcompat_report.csv"
SEEDS=(27211 2707 16404)

mkdir -p "$CONF_TOOLS_DIR"
mkdir -p "$TEST_RESULTS_DIR"

if [ ! -f "$MAIN_CSV_REPORT" ]; then
    echo "conf_tool_tag,codebase_tag,seed," \
"rand_stdout_diff,rand_stderr_diff,rand_config_diff,rand_orig_rc,rand_new_rc," \
"def_stdout_diff,def_stderr_diff,def_config_diff,def_orig_rc,def_new_rc," \
"allyes_stdout_diff,allyes_stderr_diff,allyes_config_diff,allyes_orig_rc,allyes_new_rc" \
> "$MAIN_CSV_REPORT"
fi

#When no linux kernel, clone it.
if [ ! -d "$LINUX_DIR_PATH" ]; then
    echo ">>> Cloning Linux kernel repository..."
    git clone https://github.com/torvalds/linux.git "$LINUX_DIR_PATH"
    git fetch --tags
else
    cd "$LINIX_DIR_PATH"
    git fetch --tags --depth=1
    cd "$SCRIPT_ROOT_DIR"
fi
#Getting tags
cd "$LINUX_DIR_PATH" || exit 4
ALL_TAGS=($(git tag --sort=-creatordate | grep -E '^v[0-9]+\.[0-9]+(\.[0-9]+)?$' | grep -v '\-rc' | grep -v 'v2.6.11'))
SELECTED_TAGS=("${ALL_TAGS[@]:0:5}")
cd "$SCRIPT_ROOT_DIR" || exit 5

clean_kernel() {
    git reset --hard
    git clean -xfd > /dev/null 2>&1
    make mrproper > /dev/null 2>&1
    make clean > /dev/null 2>&1
}

check_diff_exists() {
    local DIFF_FILE=$1
    [ -s "$DIFF_FILE" ] && echo "yes" || echo "no"
}

compare_configs_and_outputs() {
    diff "$DEF_OUTDIR/def_orig.config" "$DEF_OUTDIR/def_new.config" > "$DEF_OUTDIR/defconfig.config.diff"
    diff "$ALLYES_OUTDIR/allyes_orig.config" "$ALLYES_OUTDIR/allyes_new.config" > "$ALLYES_OUTDIR/allyesconfig.config.diff"
    diff "$DEF_OUTDIR/def_orig.stdout" "$DEF_OUTDIR/def_new.stdout" > "$DEF_OUTDIR/defconfig.stdout.diff"
    diff "$ALLYES_OUTDIR/allyes_orig.stdout" "$ALLYES_OUTDIR/allyes_new.stdout" > "$ALLYES_OUTDIR/allyesconfig.stdout.diff"
    diff "$DEF_OUTDIR/def_orig.stderr" "$DEF_OUTDIR/def_new.stderr" > "$DEF_OUTDIR/defconfig.stderr.diff"
    diff "$ALLYES_OUTDIR/allyes_orig.stderr" "$ALLYES_OUTDIR/allyes_new.stderr" > "$ALLYES_OUTDIR/allyesconfig.stderr.diff"
}

add_to_csv() {
    DEF_STDERR_DIFF=$(check_diff_exists "$DEF_OUTDIR/defconfig.stderr.diff")
    DEF_CONFIG_DIFF=$(check_diff_exists "$DEF_OUTDIR/defconfig.config.diff")
    DEF_STDOUT_DIFF=$(check_diff_exists "$DEF_OUTDIR/defconfig.stdout.diff")
    ALLYES_STDOUT_DIFF=$(check_diff_exists "$ALLYES_OUTDIR/allyesconfig.stdout.diff")
    ALLYES_STDERR_DIFF=$(check_diff_exists "$ALLYES_OUTDIR/allyesconfig.stderr.diff")
    ALLYES_CONFIG_DIFF=$(check_diff_exists "$ALLYES_OUTDIR/allyesconfig.config.diff")

    echo "$TAG_TOOL,$TAG_CODEBASE,$SEED," \
    "$RAND_STDOUT_DIFF,$RAND_STDERR_DIFF,$RAND_CONFIG_DIFF,$RAND_ORIG_RC,$RAND_NEW_RC," \
    "$DEF_STDOUT_DIFF,$DEF_STDERR_DIFF,$DEF_CONFIG_DIFF,$DEF_ORIG_RC,$DEF_NEW_RC," \
    "$ALLYES_STDOUT_DIFF,$ALLYES_STDERR_DIFF,$ALLYES_CONFIG_DIFF,$ALLYES_ORIG_RC,$ALLYES_NEW_RC" \
    >> "$MAIN_CSV_REPORT"
}

#extracts all conf binaries from each tag, first defconfig for compile binaries
extract_conf_from_tag() {
    local TAG=$1
    local CONF_DEST="$CONF_TOOLS_DIR/conf-${TAG}"

    if [ -f "$CONF_DEST" ]; then
        echo "OK conf binary for $TAG already exists. Skipping."
        return 0
    fi

    echo ">>> Extracting phase."
    echo ">>> Checking out $TAG"
    git checkout -f "$TAG" || exit 6

    clean_kernel

    echo ">>> Running defconfig for $TAG"
    if make defconfig > /dev/null 2>&1; then
        local CONF_PATH="scripts/kconfig/conf"
        if [ -f "$CONF_PATH" ]; then
            cp "$CONF_PATH" "$CONF_DEST"
            echo "OK Saved conf-${TAG}"
        else
            echo "NO conf binary not found in $TAG"
            exit 7
        fi
    else
        echo "NO defconfig failed for $TAG"
    fi
}

#---------------CODE---------------
cd "$LINUX_DIR_PATH" || exit 10

for TAG in "${SELECTED_TAGS[@]}"; do
    extract_conf_from_tag "$TAG"
done

for (( i=0; i<${#SELECTED_TAGS[@]}; i++ )); do
    TAG_TOOL="${SELECTED_TAGS[$i]}"
    CONF_BINARY="$CONF_TOOLS_DIR/conf-${TAG_TOOL}"

    if [ ! -f "$CONF_BINARY" ]; then
        echo "! conf binary for $TAG_TOOL not found, exitting"
        exit 9
    fi

    for (( j=i+1; j<${#SELECTED_TAGS[@]}; j++ )); do
        TAG_CODEBASE="${SELECTED_TAGS[$j]}"
        OUTDIR="$TEST_RESULTS_DIR/${TAG_TOOL}_on_${TAG_CODEBASE}"
        mkdir -p "$OUTDIR"
        DEF_OUTDIR="$OUTDIR/defconfig"
        ALLYES_OUTDIR="$OUTDIR/allyesconfig"
        mkdir -p "$DEF_OUTDIR"
        mkdir -p "$ALLYES_OUTDIR"

        #checking out and cleaning
        cd "$LINUX_DIR_PATH" || exit 11
        git checkout -f "$TAG_CODEBASE"
        clean_kernel
        rm -f .config

        #first defconfig test results in outdir. (Here i make extra one defconfig to get)
        echo ">>> Rebuilding conf binary from source..."
        make defconfig > /dev/null 2>&1
        rm -f .config
        echo ">>> Testing parser $TAG_TOOL on codebase $TAG_CODEBASE"
        echo ">>> Running defconfig with original parser..."
        make defconfig > "$DEF_OUTDIR/def_orig.stdout" 2> "$DEF_OUTDIR/def_orig.stderr"
        DEF_ORIG_RC=$?
        cp .config "$DEF_OUTDIR/def_orig.config" 2>/dev/null || touch "$DEF_OUTDIR/def_orig.config"

        # defconfig with tool conf ! no need to make defconfig beforehand, already did for original
        rm -f scripts/kconfig/conf
        cp "$CONF_BINARY" scripts/kconfig/conf
        chmod +x scripts/kconfig/conf
        echo ">>> Running defconfig with $TAG_TOOL parser"
        rm -f .config
        make defconfig > "$DEF_OUTDIR/def_new.stdout" 2> "$DEF_OUTDIR/def_new.stderr"
        DEF_NEW_RC=$?
        cp .config "$DEF_OUTDIR/def_new.config" 2>/dev/null || touch "$DEF_OUTDIR/def_new.config"

        # allyesconfig with original parser, still extra make defconfig for compiling binaries
        echo ">>> Running allyesconfig with original parser..."
        clean_kernel
        make defconfig > /dev/null 2>&1
        rm -f .config
        make allyesconfig > "$ALLYES_OUTDIR/allyes_orig.stdout" 2> "$ALLYES_OUTDIR/allyes_orig.stderr"
        ALLYES_ORIG_RC=$?
        cp .config "$ALLYES_OUTDIR/allyes_orig.config" 2>/dev/null || touch "$ALLYES_OUTDIR/allyes_orig.config"

        # allyesconfig with tool parser cleaning kernel because we need same base for tests
        echo ">>> Running allyesconfig with $TAG_TOOL parser"
        clean_kernel
        make defconfig > /dev/null 2>&1
        rm -f .config
        rm -f scripts/kconfig/conf
        cp "$CONF_BINARY" scripts/kconfig/conf
        chmod +x scripts/kconfig/conf
        make allyesconfig > "$ALLYES_OUTDIR/allyes_new.stdout" 2> "$ALLYES_OUTDIR/allyes_new.stderr"
        ALLYES_NEW_RC=$?
        cp .config "$ALLYES_OUTDIR/allyes_new.config" 2>/dev/null || touch "$ALLYES_OUTDIR/allyes_new.config"

        compare_configs_and_outputs

            for SEED in "${SEEDS[@]}"; do
                echo ">>> SEED $SEED: randconfig test $TAG_TOOL on $TAG_CODEBASE"
                SEED_OUTDIR="$TEST_RESULTS_DIR/${TAG_TOOL}_on_${TAG_CODEBASE}_seed${SEED}"
                mkdir -p "$SEED_OUTDIR"

                # randconfig with original parser, after cleaning kernel defconfig ofcourse
                cd "$LINUX_DIR_PATH" || exit 12
                git checkout -f "$TAG_CODEBASE"
                clean_kernel
                make defconfig > /dev/null 2>&1
                rm -f .config
                KCONFIG_SEED=$SEED make randconfig > "$SEED_OUTDIR/rand_orig.stdout" 2> "$SEED_OUTDIR/rand_orig.stderr"
                RAND_ORIG_RC=$?
                cp .config "$SEED_OUTDIR/rand_orig.config" 2>/dev/null || touch "$SEED_OUTDIR/rand_orig.config"

                # randconfig with tool parser
                rm -f scripts/kconfig/conf
                cp "$CONF_BINARY" scripts/kconfig/conf
                chmod +x scripts/kconfig/conf
                rm -f .config
                KCONFIG_SEED=$SEED make randconfig > "$SEED_OUTDIR/rand_new.stdout" 2> "$SEED_OUTDIR/rand_new.stderr"
                RAND_NEW_RC=$?
                cp .config "$SEED_OUTDIR/rand_new.config" 2>/dev/null || touch "$SEED_OUTDIR/rand_new.config"
                
                diff "$SEED_OUTDIR/rand_orig.stdout" "$SEED_OUTDIR/rand_new.stdout" > "$SEED_OUTDIR/rand_stdout.diff"
                diff "$SEED_OUTDIR/rand_orig.stderr" "$SEED_OUTDIR/rand_new.stderr" > "$SEED_OUTDIR/rand_stderr.diff"
                diff "$SEED_OUTDIR/rand_orig.config" "$SEED_OUTDIR/rand_new.config" > "$SEED_OUTDIR/rand_config.diff"
                
                RAND_STDOUT_DIFF=$([ -s "$SEED_OUTDIR/rand_stdout.diff" ] && echo "yes" || echo "no")
                RAND_STDERR_DIFF=$([ -s "$SEED_OUTDIR/rand_stderr.diff" ] && echo "yes" || echo "no")
                RAND_CONFIG_DIFF=$([ -s "$SEED_OUTDIR/rand_config.diff" ] && echo "yes" || echo "no")
                echo "randconfig test completed for SEED $SEED ($TAG_TOOL on $TAG_CODEBASE)"
                # write to CSV
                add_to_csv
                echo "reesults for $TAG_TOOL on $TAG_CODEBASE (SEED $SEED) written to CSV"
            done

        
    done
done
