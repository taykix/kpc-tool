#!/bin/bash

# === Configuration ===
SCRIPT_ROOT_DIR="$(pwd)"
LINUX_DIR_NAME="linux"
LINUX_DIR_PATH="$SCRIPT_ROOT_DIR/$LINUX_DIR_NAME"
RESULTS_DIR="$SCRIPT_ROOT_DIR/test_results"
CSV_REPORT="$SCRIPT_ROOT_DIR/backcompat_report.csv"
SEEDS=()
for i in {1..3}; do
    SEEDS+=($RANDOM)
done                

mkdir -p "$RESULTS_DIR"
echo "TAG_PARSER,TAG_TESTED,SEED,STDOUT_DIFF,STDERR_DIFF,CONFIG_DIFF,ORIG_EXIT_CODE,NEW_EXIT_CODE,BINDINGS_OK,DEFCONFIG_STDERR_DIFF_ORIG_VS_COPIED,DEFCONFIG_CONFIG_DIFF_ORIG_VS_COPIED,DEFCONFIG_STDOUT_DIFF_ORIG_VS_COPIED,ORIG_DEFCONFIG_RC,COPIED_DEFCONFIG_RC,ALLYESCONFIG_STDERR_DIFF_ORIG_VS_COPIED,ALLYESCONFIG_CONFIG_DIFF_ORIG_VS_COPIED,ALLYESCONFIG_STDOUT_DIFF_ORIG_VS_COPIED,ALLYESCONFIG_STDOUT_DIFF_ORIG_VS_COPIED,ORIG_ALLYESCONFIG_RC,COPIED_ALLYESCONFIG_RC" > "$CSV_REPORT"

if [ ! -d "$LINUX_DIR_PATH" ]; then
    echo ">>> Cloning Linux kernel repository..."
    git clone https://github.com/torvalds/linux.git "$LINUX_DIR_PATH"
    git fetch --tags
fi

# === Step 1: Get ALL version tags ===
cd "$LINUX_DIR_PATH" || exit 4
ALL_TAGS=($(git tag --sort=-creatordate | grep -E '^v[0-9]+\.[0-9]+$'))
SELECTED_TAGS=("${ALL_TAGS[@]:0:7}")
cd "$SCRIPT_ROOT_DIR" || exit 5

# === Step 2: Extract each tag's parser ===
mkdir -p "$SCRIPT_ROOT_DIR/parsers"
for TAG_X in "${SELECTED_TAGS[@]}"; do
    echo ">>> Extracting parser from $TAG_X"
    cd "$LINUX_DIR_PATH" || exit 6
    git checkout -f "$TAG_X"
    git clean -xfd > /dev/null 2>&1
    git reset --hard

    if [ -d "scripts/kconfig" ]; then
        PARSER_DIR="$SCRIPT_ROOT_DIR/parsers/$TAG_X"
        mkdir -p "$PARSER_DIR"
        cp -r scripts/kconfig/* "$PARSER_DIR/"
    else
        echo "Warning: scripts/kconfig not found in $TAG_X"
    fi
done

# === Step 3: Run tests ===
clean_and_reset() {
    git reset --hard
    git clean -xfd > /dev/null 2>&1
    make mrproper > /dev/null 2>&1
    make clean > /dev/null 2>&1
}

run_defconfig_test() {
    echo ">>> Running defconfig test..."
    cd "$LINUX_DIR_PATH" || exit 7
    git checkout -f "$TAG_Y"
    clean_and_reset
    make defconfig > "$OUTDIR/original_defconfig.stdout" 2> "$OUTDIR/original_defconfig.stderr"
    ORIG_DEFCONFIG_RC=$?
    cp .config "$OUTDIR/original_defconfig.config" 2>/dev/null || touch "$OUTDIR/original_defconfig.config"
}

run_allyesconfig_test() {
    echo ">>> Running allyesconfig test..."
    cd "$LINUX_DIR_PATH" || exit 8
    git checkout -f "$TAG_Y"
    clean_and_reset
    make allyesconfig > "$OUTDIR/original_allyesconfig.stdout" 2> "$OUTDIR/original_allyesconfig.stderr"
    ORIG_ALLYESCONFIG_RC=$?
    cp .config "$OUTDIR/original_allyesconfig.config" 2>/dev/null || touch "$OUTDIR/original_allyesconfig.config"
}

run_defconfig_with_copied_kconfig() {
    echo ">>> Running defconfig test with copied kconfig..."
    cd "$LINUX_DIR_PATH" || exit 9
    git checkout -f "$TAG_Y"
    clean_and_reset
    rm -rf scripts/kconfig
    cp -r "$PARSER_X_PATH" scripts/kconfig
    make defconfig > "$OUTDIR/copied_defconfig.stdout" 2> "$OUTDIR/copied_defconfig.stderr"
    COPIED_DEFCONFIG_RC=$?
    cp .config "$OUTDIR/copied_defconfig.config" 2>/dev/null || touch "$OUTDIR/copied_defconfig.config"
}

run_allyesconfig_with_copied_kconfig() {
    echo ">>> Running allyesconfig test with copied kconfig..."
    cd "$LINUX_DIR_PATH" || exit 10
    git checkout -f "$TAG_Y"
    clean_and_reset
    rm -rf scripts/kconfig
    cp -r "$PARSER_X_PATH" scripts/kconfig
    make allyesconfig > "$OUTDIR/copied_allyesconfig.stdout" 2> "$OUTDIR/copied_allyesconfig.stderr"
    COPIED_ALLYESCONFIG_RC=$?
    cp .config "$OUTDIR/copied_allyesconfig.config" 2>/dev/null || touch "$OUTDIR/copied_allyesconfig.config"
}

# === Step 4: Compare the outputs ===
compare_configs_and_outputs() {
    diff "$OUTDIR/original_defconfig.config" "$OUTDIR/copied_defconfig.config" > "$OUTDIR/defconfig.config.diff"
    diff "$OUTDIR/original_allyesconfig.config" "$OUTDIR/copied_allyesconfig.config" > "$OUTDIR/allyesconfig.config.diff"
    diff "$OUTDIR/original_defconfig.stdout" "$OUTDIR/copied_defconfig.stdout" > "$OUTDIR/defconfig.stdout.diff"
    diff "$OUTDIR/original_allyesconfig.stdout" "$OUTDIR/copied_allyesconfig.stdout" > "$OUTDIR/allyesconfig.stdout.diff"
    diff "$OUTDIR/original_defconfig.stderr" "$OUTDIR/copied_defconfig.stderr" > "$OUTDIR/defconfig.stderr.diff"
    diff "$OUTDIR/original_allyesconfig.stderr" "$OUTDIR/copied_allyesconfig.stderr" > "$OUTDIR/allyesconfig.stderr.diff"
}

# Helper function to check if a diff exists and is non-empty
check_diff_exists() {
    local DIFF_FILE=$1
    if [ -s "$DIFF_FILE" ]; then
        echo "yes"
    else
        echo "no"
    fi
}

# Add results to CSV
add_to_csv() {
    # Check for differences in stderr and defconfig diffs
    DEFCONFIG_STDERR_DIFF_ORIG_VS_COPIED=$(check_diff_exists "$OUTDIR/defconfig.stderr.diff")
    DEFCONFIG_CONFIG_DIFF_ORIG_VS_COPIED=$(check_diff_exists "$OUTDIR/defconfig.config.diff")
    DEFCONFIG_STDOUT_DIFF_ORIG_VS_COPIED=$(check_diff_exists "$OUTDIR/defconfig.stdout.diff")
    ALLYESCONFIG_STDERR_DIFF_ORIG_VS_COPIED=$(check_diff_exists "$OUTDIR/allyesconfig.stderr.diff")
    ALLYESCONFIG_CONFIG_DIFF_ORIG_VS_COPIED=$(check_diff_exists "$OUTDIR/allyesconfig.config.diff")
    ALLYESCONFIG_STDOUT_DIFF_ORIG_VS_COPIED=$(check_diff_exists "$OUTDIR/allyesconfig.stdout.diff")


    echo "$TAG_X,$TAG_Y,$SEED,$STDOUT_DIFF,$STDERR_DIFF,$CONFIG_DIFF,$ORIG_RC,$NEW_RC,$BINDINGS_OK,$DEFCONFIG_STDERR_DIFF_ORIG_VS_COPIED,$DEFCONFIG_CONFIG_DIFF_ORIG_VS_COPIED,$DEFCONFIG_STDOUT_DIFF_ORIG_VS_COPIED,$ORIG_DEFCONFIG_RC,$COPIED_DEFCONFIG_RC,$ALLYESCONFIG_STDERR_DIFF_ORIG_VS_COPIED,$ALLYESCONFIG_CONFIG_DIFF_ORIG_VS_COPIED,$ALLYESCONFIG_STDOUT_DIFF_ORIG_VS_COPIED,$ALLYESCONFIG_STDOUT_DIFF_ORIG_VS_COPIED,$ORIG_ALLYESCONFIG_RC,$COPIED_ALLYESCONFIG_RC" >> "$CSV_REPORT"
}

for (( i=0; i<${#SELECTED_TAGS[@]}; i++ )); do
    TAG_X="${SELECTED_TAGS[$i]}"
    PARSER_X_PATH="$SCRIPT_ROOT_DIR/parsers/$TAG_X"

    echo "==== Running tests with parser from $TAG_X ===="

    OUTDIR="$RESULTS_DIR/${TAG_X}_tests"
    mkdir -p "$OUTDIR"


    # For each seed, run the tests and capture the output differences
    for (( j=i+1; j<${#SELECTED_TAGS[@]}; j++ )); do
        TAG_Y="${SELECTED_TAGS[$j]}"

    	# === Step 5: Run defconfig and allyesconfig tests BEFORE seed loop ===
    	run_defconfig_test
    	run_allyesconfig_test
    	run_defconfig_with_copied_kconfig
    	run_allyesconfig_with_copied_kconfig

    	# Compare the results (original vs copied)
    	compare_configs_and_outputs
        for SEED in "${SEEDS[@]}"; do
            SEED_OUTDIR="$RESULTS_DIR/${TAG_X}_on_${TAG_Y}_seed${SEED}"
            mkdir -p "$SEED_OUTDIR"

            # 1. Build and run original parser of TAG_Y
            cd "$LINUX_DIR_PATH" || exit 11
            git checkout -f "$TAG_Y"
            clean_and_reset
            KCONFIG_SEED=$SEED make randconfig > "$SEED_OUTDIR/orig.stdout" 2> "$SEED_OUTDIR/orig.stderr"
            ORIG_RC=$?
            cp .config "$SEED_OUTDIR/orig.config" 2>/dev/null || touch "$SEED_OUTDIR/orig.config"

            # 2. Replace with TAG_X parser and rerun
            git reset --hard
            git clean -xfd
            make mrproper > /dev/null 2>&1
            make clean > /dev/null 2>&1
            rm -rf scripts/kconfig
            cp -r "$PARSER_X_PATH" scripts/kconfig

            rm -f .config
            if make -C scripts/kconfig conf > /dev/null 2>&1; then
                BINDINGS_OK=1
            else
                BINDINGS_OK=0
            fi

            KCONFIG_SEED=$SEED make randconfig > "$SEED_OUTDIR/new.stdout" 2> "$SEED_OUTDIR/new.stderr"
            NEW_RC=$?
            cp .config "$SEED_OUTDIR/new.config" 2>/dev/null || touch "$SEED_OUTDIR/new.config"

            # 3. Compare outputs
            diff "$SEED_OUTDIR/orig.stdout" "$SEED_OUTDIR/new.stdout" > "$SEED_OUTDIR/stdout.diff"
            diff "$SEED_OUTDIR/orig.stderr" "$SEED_OUTDIR/new.stderr" > "$SEED_OUTDIR/stderr.diff"
            diff "$SEED_OUTDIR/orig.config" "$SEED_OUTDIR/new.config" > "$SEED_OUTDIR/config.diff"

            STDOUT_DIFF=$([ -s "$SEED_OUTDIR/stdout.diff" ] && echo "yes" || echo "no")
            STDERR_DIFF=$([ -s "$SEED_OUTDIR/stderr.diff" ] && echo "yes" || echo "no")
            CONFIG_DIFF=$([ -s "$SEED_OUTDIR/config.diff" ] && echo "yes" || echo "no")

            # Add results to CSV (one line for each test)
            add_to_csv
        done
    done
done
