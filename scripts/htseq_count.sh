#!/bin/bash

#===============================================================================
# HTSeq-Count Gene Expression Quantification Script
#
# This script performs read counting on aligned BAM files using HTSeq-count.
# It counts reads overlapping genomic features (exons) at gene level using
# the provided GTF annotation file.
#
# Input:
#   - Sorted BAM files from HISAT2 alignment
#   - GTF annotation file
#
# Output:
#   - HTSeq count files per sample
#
# Requirements:
#   - HTSeq: Framework for processing sequencing data
#   - SAMtools: Sequence Alignment/Map format utilities
#
#===============================================================================

# Source utility functions from utils.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Note: All variables are now defined and exported from main.sh
# Variables available: INPUT_DIR, ALIGNMENT_DIR, HTSEQ_COUNT_DIR,
# HTSEQ_FORMAT, HTSEQ_STRANDED, HTSEQ_MODE, HTSEQ_MIN_QUAL,
# HTSEQ_FEATURE_TYPE, HTSEQ_IDATTR, HTSEQ_ADDITIONAL_ATTR, HTSEQ_THREADS,
# ANNOTATION_FILE

# For compatibility, create local aliases for HTSeq parameters
FORMAT="$HTSEQ_FORMAT"
STRANDED="$HTSEQ_STRANDED"
MODE="$HTSEQ_MODE"
MIN_QUAL="$HTSEQ_MIN_QUAL"
FEATURE_TYPE="$HTSEQ_FEATURE_TYPE"
IDATTR="$HTSEQ_IDATTR"
ADDITIONAL_ATTR="$HTSEQ_ADDITIONAL_ATTR"

#===============================================================================
# Validation checks
#===============================================================================

# Check if required tools are available
command -v samtools &> /dev/null || error_exit "samtools is not installed. Please install SAMtools to continue."
command -v htseq-count &> /dev/null || error_exit "htseq-count is not installed. Please install HTSeq to continue."

print_success "All required tools are available."
echo ""

# Check if input directory exists
if [[ ! -d "$INPUT_DIR" ]]; then
    error_exit "Input directory '$INPUT_DIR' not found."
fi

# Check if annotation GTF file exists
if [[ ! -f "$INPUT_DIR/$ANNOTATION_FILE" ]]; then
    error_exit "Annotation file '$INPUT_DIR/$ANNOTATION_FILE' not found."
fi

# Check if alignment directory exists
if [[ ! -d "$ALIGNMENT_DIR" ]]; then
    error_exit "Alignment directory '$ALIGNMENT_DIR' not found. Run alignment script first."
fi

# Check if SAM/BAM files exist
SAM_COUNT=$(ls "$ALIGNMENT_DIR"/*.sam 2>/dev/null | wc -l)
if [[ $SAM_COUNT -eq 0 ]]; then
    error_exit "No SAM files found in '$ALIGNMENT_DIR'. Run alignment script first."
fi

print_info "Found $SAM_COUNT SAM files to process."

#===============================================================================
# Create output directories
#===============================================================================

print_info "Creating output directories..."
mkdir -p "$HTSEQ_COUNT_DIR" || error_exit "Failed to create directory '$HTSEQ_COUNT_DIR'."
print_success "Output directories created."

#===============================================================================
# Function to run HTSeq-count on BAM files
#===============================================================================

run_htseq_count() {
    local bam_file="$1"
    local gtf_file="$2"
    local output_dir="$3"
    
    # Extract sample name from filename
    local sample_name=$(basename "$bam_file" .sorted.bam)
    
    # Define output file
    local count_file="$output_dir/${sample_name}.htseq"
    local log_file="$output_dir/${sample_name}.log"

    
    print_info "Running HTSeq-count on: $sample_name"
    
    # Run HTSeq-count with specified parameters
    htseq-count \
        --format "$FORMAT" \
        --stranded "$STRANDED" \
        --mode "$MODE" \
        --minaqual "$MIN_QUAL" \
        --type "$FEATURE_TYPE" \
        --idattr "$IDATTR" \
        --additional-attr "$ADDITIONAL_ATTR" \
        "$bam_file" "$gtf_file" \
        > "$count_file" 2> "$log_file" || \
        error_exit "HTSeq-count failed for $sample_name"
    
    
    print_success "HTSeq-count complete: $sample_name"
    
    # Display read count statistics
    local total_counts=$(grep -v "^__" "$count_file" | wc -l)
    local assigned=$(grep -v "^__" "$count_file" | awk '$2 > 0' | wc -l)
    
    echo "  - Features counted: $total_counts"
    echo "  - Features with reads: $assigned"
}



#===============================================================================
# Main execution
#===============================================================================

echo ""
print_info "Starting gene expression quantification pipeline..."
echo ""

# Run HTSeq-count on sorted BAM files
print_info "Starting HTSeq-count gene expression quantification..."
echo ""

for bam_file in "$ALIGNMENT_DIR"/*.sorted.bam; do
    if [[ -f "$bam_file" ]]; then
        run_htseq_count "$bam_file" "$INPUT_DIR/$ANNOTATION_FILE" "$HTSEQ_COUNT_DIR"
        echo ""
    fi
done



#===============================================================================
# Final summary
#===============================================================================

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Gene expression quantification completed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Summary:"
echo "  Annotation file: $ANNOTATION_FILE"
echo "  Alignment directory: $ALIGNMENT_DIR"
echo "  Samples processed: $SAM_COUNT"
echo "  Count results: $HTSEQ_COUNT_DIR"
echo ""
echo "HTSeq count output files:"
ls -lh "$HTSEQ_COUNT_DIR"/*.htseq.txt 2>/dev/null | awk '{print "  " $9}' || echo "  No count files found"
