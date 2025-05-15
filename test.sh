#!/bin/bash
set -o pipefail

SCRIPT_ROOT_DIR=$(pwd)

RESULTS_DIR_NAME="test_results"
RESULTS_DIR="$SCRIPT_ROOT_DIR/$RESULTS_DIR_NAME" 
mkdir -p "$RESULTS_DIR"

LINUX_DIR_NAME="linux"
LINUX_DIR_PATH="$SCRIPT_ROOT_DIR/$LINUX_DIR_NAME" 

# Clone or update the Linux kernel repo
if [ ! -d "$LINUX_DIR_PATH" ]; then
	echo "Cloning Kernel into $LINUX_DIR_PATH"
    git clone https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git "$LINUX_DIR_PATH"
	git -C "$LINUX_DIR_PATH" fetch --tags
else
	echo "Kernel is already there in $LINUX_DIR_PATH, so resetting."
	cd "$LINUX_DIR_PATH"
	git reset --hard HEAD
	git fetch origin 
	git checkout -f origin/master 
	git reset --hard origin/master
	git clean -xfd
    git fetch --tags 
	cd "$SCRIPT_ROOT_DIR" 
fi

# "current_parser" 
NEW_KCONFIG_BASE_DIR_NAME="current_parser"
NEW_KCONFIG_PATH="$SCRIPT_ROOT_DIR/$NEW_KCONFIG_BASE_DIR_NAME"
cd "$LINUX_DIR_PATH"
git pull

rm -rf "$NEW_KCONFIG_PATH"
mkdir -p "$NEW_KCONFIG_PATH"
if [ -d "scripts/kconfig" ]; then
    echo "Copying latest scripts/kconfig from $LINUX_DIR_PATH/scripts/kconfig to $NEW_KCONFIG_PATH/"
    cp -r scripts/kconfig/* "$NEW_KCONFIG_PATH/" # İçeriği kopyala, dizini değil
else
    echo "ERROR: scripts/kconfig not found in $LINUX_DIR_PATH on the latest branch. Cannot proceed."
    exit 1
fi
cd "$SCRIPT_ROOT_DIR"

RANDOM_TAGS=("v6.14" "v6.13" "v6.12" "v6.11" "v6.10" "v6.9" "v6.8" "v6.7" "v6.6")

SEEDS=()
for i in {1..3}; do
    SEEDS+=($RANDOM)
done

# Initializating report file
REPORT="$RESULTS_DIR/summary_report.txt"
echo "Kernel Kconfig Parser Compatibility Report" > "$REPORT"
echo "Tested tags: ${RANDOM_TAGS[*]}" >> "$REPORT"
echo "Seeds: ${SEEDS[*]}" >> "$REPORT"
echo "" >> "$REPORT"


for TAG in "${RANDOM_TAGS[@]}"; do
    echo "------------------------------------"
    echo "Processing tag: $TAG"
    echo "------------------------------------"

    cd "$LINUX_DIR_PATH"
    if ! git checkout -f "$TAG"; then
        echo "ERROR: Failed to checkout tag $TAG. Skipping."
        echo "Tag: $TAG, Status: CHECKOUT_FAILED" >> "$REPORT"
        cd "$SCRIPT_ROOT_DIR"
        continue
    fi
	if ! git reset --hard; then
        echo "ERROR: Failed to reset --hard after checking out tag $TAG. Skipping."
        echo "Tag: $TAG, Status: RESET_FAILED" >> "$REPORT"
        cd "$SCRIPT_ROOT_DIR"
        continue
    fi
	git clean -xfd
    echo "Cleaning build for $TAG (make mrproper)..."
    make mrproper > /dev/null 2>&1 || echo "Warning: make mrproper might have failed for $TAG"
    cd "$SCRIPT_ROOT_DIR"

    for SEED in "${SEEDS[@]}"; do
        echo "  Seed: $SEED for tag: $TAG"
        OUTDIR="$RESULTS_DIR/${TAG}_${SEED}"
        mkdir -p "$OUTDIR"

        # --- Original parser ---
        echo "    Running with original parser..."
        cd "$LINUX_DIR_PATH"
		git clean -xfd
        make clean > /dev/null 2>&1
		make mrproper > /dev/null 2>&1
        rm -f .config

        KCONFIG_SEED=$SEED make randconfig > "$OUTDIR/orig.stdout" 2> "$OUTDIR/orig.stderr"
        ORIG_STATUS=$?
        if [ -f .config ]; then
            cp .config "$OUTDIR/orig.config"
        else
            touch "$OUTDIR/orig.config"
            echo "Warning: .config not created by original parser ($TAG, $SEED)" >> "$OUTDIR/orig.stderr"
        fi
        cd "$SCRIPT_ROOT_DIR"

        # --- New parser ---
        echo "    Preparing and running with NEW parser..."
        cd "$LINUX_DIR_PATH"
		
		echo "cleaning old $TAG s kconfig"
        rm -rf scripts/kconfig
        
        echo "    Copying new kconfig from $NEW_KCONFIG_PATH to $LINUX_DIR_PATH/scripts/"
        cp -r "$NEW_KCONFIG_PATH" "scripts/kconfig"

        # Clearn before make rand
        make clean > /dev/null 2>&1
        rm -f .config

        KCONFIG_SEED=$SEED make randconfig > "$OUTDIR/new.stdout" 2> "$OUTDIR/new.stderr"
        NEW_STATUS=$?
        if [ -f .config ]; then
            cp .config "$OUTDIR/new.config"
        else
            touch "$OUTDIR/new.config"
            echo "Warning: .config not created by new parser ($TAG, $SEED)" >> "$OUTDIR/new.stderr"
        fi
        
        cd "$SCRIPT_ROOT_DIR" 

        # compairing results
        echo "    Comparing results..."
        diff "$OUTDIR/orig.stdout" "$OUTDIR/new.stdout" > "$OUTDIR/stdout.diff"
        diff "$OUTDIR/orig.stderr" "$OUTDIR/new.stderr" > "$OUTDIR/stderr.diff"
        diff "$OUTDIR/orig.config" "$OUTDIR/new.config" > "$OUTDIR/config.diff"

        # report
        {
            echo "Tag: $TAG, Seed: $SEED"
            echo "  Original parser exit: $ORIG_STATUS"
            echo "  New parser exit: $NEW_STATUS"
            if [ -s "$OUTDIR/stdout.diff" ]; then
                echo "  stdout differs (see $OUTDIR/stdout.diff)"
            else
                echo "  stdout identical"
            fi
            if [ -s "$OUTDIR/stderr.diff" ]; then
                echo "  stderr differs (see $OUTDIR/stderr.diff)"
            else
                echo "  stderr identical"
            fi
            if [ -s "$OUTDIR/config.diff" ]; then
                echo "  .config differs (see $OUTDIR/config.diff)"
            else
                echo "  .config identical"
            fi
            echo ""
        } >> "$REPORT"
    done
done 


cd "$LINUX_DIR_PATH"
if git show-ref --verify --quiet refs/heads/master; then
    git checkout master
elif git show-ref --verify --quiet refs/heads/main; then
    git checkout main
fi
cd "$SCRIPT_ROOT_DIR"

echo "Testing completed. Results are in $RESULTS_DIR"
echo "See $REPORT for summary."

