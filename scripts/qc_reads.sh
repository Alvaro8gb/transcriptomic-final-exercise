
#!/bin/bash

#===============================================================================
# Trimmed FastQC Quality Control Analysis Script
#
# This script performs quality assessment on trimmed FASTQ files using FastQC
#
# Input:
#   - Trimmed paired-end FASTQ files from adapter trimming
#
# Output:
#   - FastQC HTML reports per file
#
# Requirements:
#   - FastQC: Quality control tool for high-throughput sequence data
#
#===============================================================================

# Source utility functions from utils.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"


#===============================================================================
# Validation checks
#===============================================================================

# Check if FASTQ files exist in input directory
FASTQ_COUNT=$(ls "$INPUT_DIR"/*.fastq 2>/dev/null | wc -l)
if [[ $FASTQ_COUNT -eq 0 ]]; then
    error_exit "No FASTQ files found in '$OUTPUT_TRIMMED_DIR'."
fi

print_info "Found $FASTQ_COUNT FASTQ files to process."


# Check if FASTQ files exist in input directory
FASTQ_COUNT_TRIMMED=$(ls "$OUTPUT_TRIMMED_DIR"/*.fastq 2>/dev/null | wc -l)
if [[ $FASTQ_COUNT -eq 0 ]]; then
    error_exit "No FASTQ files found in '$OUTPUT_TRIMMED_DIR'."
fi

print_info "Found $FASTQ_COUNT_TRIMMED trimmed FASTQ files to process."

#===============================================================================
# Create output directories
#===============================================================================

print_info "Creating output directories..."
mkdir -p "$OUTPUT_FASTQC_DIR" || error_exit "Failed to create directory '$OUTPUT_FASTQC_DIR'."
print_success "Output directories created."

#===============================================================================
# Function to run FastQC on FASTQ files
#===============================================================================

run_fastqc_analysis() {
    local input_dir="$1"
    local output_dir="$2"
    local num_threads="$3"
    
    print_info "Running FastQC analysis on trimmed FASTQ files..."
    
    # Run FastQC with quality metrics
    fastqc \
        "$input_dir"/*.fastq \
        -o "$output_dir" \
        --threads "$num_threads" \
        --memory "$FASTQC_MEMORY" || \
        error_exit "FastQC analysis failed."
    
    print_success "FastQC analysis complete."
}


#===============================================================================
# Main execution
#===============================================================================

echo ""
print_info "Starting trimmed FastQC quality control analysis..."
echo ""

# Run FastQC analysis

run_fastqc_analysis "$INPUT_DIR" "$OUTPUT_FASTQC_DIR" "$FASTQC_THREADS"
run_fastqc_analysis "$OUTPUT_TRIMMED_DIR" "$OUTPUT_FASTQC_DIR" "$FASTQC_THREADS"


#===============================================================================
# Final summary
#===============================================================================

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Trimmed FastQC analysis completed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Summary:"
echo "  Input directory: $OUTPUT_TRIMMED_DIR"
echo "  Files processed: $FASTQ_COUNT"
echo "  FastQC results: $OUTPUT_FASTQC_DIR"
echo "  MultiQC report: $OUTPUT_FASTQC_MULTIQC_DIR/multiqc_report.html"
echo ""
echo "Generated FastQC reports:"
ls -lh "$OUTPUT_FASTQC_DIR"/*_fastqc.html 2>/dev/null | awk '{print "  " $9}' || echo "  No FastQC reports found"
echo ""

