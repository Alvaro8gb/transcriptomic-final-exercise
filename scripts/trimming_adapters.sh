#!/bin/bash

#===============================================================================
# RNA-Seq Adapter Trimming Script
#
# This script performs quality-based adapter trimming on paired-end FASTQ files
# using Cutadapt. It removes sequencing adapters, low-quality bases, and
# short reads while maintaining read pairing information.
#
# Requirements:
#   - Cutadapt: Adapter trimming tool for high-throughput sequencing data
#
# Parameters:
#   - Input: Paired-end FASTQ files
#   - Quality threshold: 20 (Phred score)
#   - Minimum length: 20 bp
#   - Adapter sequences: Illumina TruSeq adapters
#
#===============================================================================

# Source utility functions from utils.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Note: All variables are now defined and exported from main.sh
# Variables available: BASE_DIR, INPUT_DIR, BASE_OUT, OUTPUT_TRIMMED_DIR,
# QUALITY_THRESHOLD, MIN_LENGTH, TRIMMING_THREADS, ADAPTER_R1, ADAPTER_R2

#===============================================================================
# Validation checks
#===============================================================================

# Check if input directory exists
if [[ ! -d "$INPUT_DIR" ]]; then
    error_exit "Input directory '$INPUT_DIR' not found."
fi

# Check if FASTQ files exist
FASTQ_COUNT=$(ls "$INPUT_DIR"/*.fastq 2>/dev/null | wc -l)
if [[ $FASTQ_COUNT -eq 0 ]]; then
    error_exit "No FASTQ files found in '$INPUT_DIR'."
fi

if [[ $((FASTQ_COUNT % 2)) -ne 0 ]]; then
    error_exit "Unpaired FASTQ files detected. Expected even number of files for paired-end data."
fi

#===============================================================================
# Create output directory
#===============================================================================

print_info "Creating trimmed output directory..."
mkdir -p "$OUTPUT_TRIMMED_DIR" || error_exit "Failed to create directory '$OUTPUT_TRIMMED_DIR'."
print_success "Output directory created: $OUTPUT_TRIMMED_DIR"

#===============================================================================
# Function to trim paired-end FASTQ files
#===============================================================================

trim_paired_reads() {
    local read1="$1"
    local read2="$2"
    local output_dir="$3"
    
    # Extract sample name from filename
    local sample_name=$(basename "$read1" _1.fastq)
    
    # Define output file paths
    local trimmed_r1="$output_dir/${sample_name}_1.trimmed.fastq"
    local trimmed_r2="$output_dir/${sample_name}_2.trimmed.fastq"
    local report="$output_dir/${sample_name}.trimming_report.txt"
    
    print_info "Trimming sample: $sample_name"
    
    # Run cutadapt with paired-end options
    cutadapt \
        -a "$ADAPTER_R1" \
        -A "$ADAPTER_R2" \
        -q "$QUALITY_THRESHOLD" \
        -m "$MIN_LENGTH" \
        --cores="$TRIMMING_THREADS" \
        -o "$trimmed_r1" \
        -p "$trimmed_r2" \
        "$read1" "$read2" \
        > "$report" 2>&1 || error_exit "Trimming failed for $sample_name"
    
    print_success "Trimmed: $sample_name"
    
    # Extract and display key statistics
    local reads_processed=$(grep "Total basepairs processed:" "$report" | awk '{print $4}')
    local reads_trimmed=$(grep "Total written (filtered): " "$report" | head -1 | awk '{print $4}')
    
    echo "  - Reads processed: $reads_processed"
    echo "  - Reads retained: $reads_trimmed"
}

#===============================================================================
# Main trimming process
#===============================================================================

print_info "Starting adapter trimming process..."
echo ""

# Array to store R1 and R2 files
declare -a R1_FILES
declare -a R2_FILES

# Find and sort paired FASTQ files
for file in "$INPUT_DIR"/*_1.fastq; do
    if [[ -f "$file" ]]; then
        R1_FILES+=("$file")
        # Find corresponding R2 file
        R2_FILE="${file/_1.fastq/_2.fastq}"
        if [[ -f "$R2_FILE" ]]; then
            R2_FILES+=("$R2_FILE")
        else
            error_exit "Corresponding R2 file not found for: $file"
        fi
    fi
done

# Trim each paired-end sample
for i in "${!R1_FILES[@]}"; do
    trim_paired_reads "${R1_FILES[$i]}" "${R2_FILES[$i]}" "$OUTPUT_TRIMMED_DIR"
done

#===============================================================================
# Summary statistics
#===============================================================================

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Adapter trimming completed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Summary:"
echo "  Input directory: $INPUT_DIR"
echo "  Output directory: $OUTPUT_TRIMMED_DIR"
echo "  Quality threshold: $QUALITY_THRESHOLD"
echo "  Minimum read length: $MIN_LENGTH bp"
echo "  Number of samples processed: ${#R1_FILES[@]}"
echo ""
echo "Trimmed files:"
ls -lh "$OUTPUT_TRIMMED_DIR"/*.trimmed.fastq 2>/dev/null || echo "  No trimmed files found"
echo ""
echo "Trimming reports:"
ls -lh "$OUTPUT_TRIMMED_DIR"/*.trimming_report.txt 2>/dev/null || echo "  No reports found"
echo ""
