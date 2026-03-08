#!/bin/bash

#===============================================================================
# SAM to BAM Processing and Indexing Script
#
# This script converts SAM alignment files to sorted and indexed BAM format
# using SAMtools. BAM files are required for downstream analysis tools like
# HTSeq-count and variant calling.
#
# Input:
#   - SAM files from HISAT2 alignment
#
# Output:
#   - Sorted BAM files
#   - BAM index files (.bai)
#
# Requirements:
#   - SAMtools: Sequence Alignment/Map format utilities
#
#===============================================================================

# Source utility functions from utils.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Note: All variables are now defined and exported from main.sh
# Variables available: ALIGNMENT_DIR, MULTIQC_ALIGN_DIR, SAMTOOLS_THREADS, COMPRESSION_LEVEL

#===============================================================================
# Validation checks
#===============================================================================

# Check if required tools are available
command -v samtools &> /dev/null || error_exit "samtools is not installed. Please install SAMtools to continue."
command -v multiqc &> /dev/null || error_exit "multiqc is not installed. Please install MultiQC to continue."

print_success "All required tools are available."
echo ""

# Check if alignment directory exists
if [[ ! -d "$ALIGNMENT_DIR" ]]; then
    error_exit "Alignment directory '$ALIGNMENT_DIR' not found. Run alignment script first."
fi

# Check if SAM files exist
SAM_COUNT=$(ls "$ALIGNMENT_DIR"/*.sam 2>/dev/null | wc -l)
if [[ $SAM_COUNT -eq 0 ]]; then
    error_exit "No SAM files found in '$ALIGNMENT_DIR'."
fi

print_info "Found $SAM_COUNT SAM files to process."

#===============================================================================
# Create output directories
#===============================================================================

print_info "Creating output directories..."
mkdir -p "$MULTIQC_ALIGN_DIR" || error_exit "Failed to create directory '$MULTIQC_ALIGN_DIR'."
print_success "Output directories created."

#===============================================================================
# Function to convert SAM to BAM
#===============================================================================

convert_sam_to_bam() {
    local sam_file="$1"
    local output_dir="$2"
    
    # Extract sample name from filename
    local sample_name=$(basename "$sam_file" .sam)
    
    # Define output file paths
    local bam_file="$output_dir/${sample_name}.bam"
    
    print_info "Converting SAM to BAM: $sample_name"
    
    # Convert SAM to BAM using samtools view
    samtools view -b -S -@ "$SAMTOOLS_THREADS" "$sam_file" -o "$bam_file" || \
        error_exit "SAM to BAM conversion failed for $sample_name"
    
    print_success "SAM to BAM conversion complete: $sample_name"
}

#===============================================================================
# Function to sort BAM file
#===============================================================================

sort_bam_file() {
    local bam_file="$1"
    local output_dir="$2"
    
    # Extract sample name from filename
    local sample_name=$(basename "$bam_file" .bam)
    
    # Define output file
    local sorted_bam="$output_dir/${sample_name}.sorted.bam"
    
    print_info "Sorting BAM file: $sample_name"
    
    # Sort BAM file
    samtools sort -@ "$SAMTOOLS_THREADS" -l "$COMPRESSION_LEVEL" \
        "$bam_file" -o "$sorted_bam" || \
        error_exit "BAM sorting failed for $sample_name"
    
    # Remove unsorted BAM
    rm -f "$bam_file"
    
    print_success "BAM sorting complete: $sample_name"
    
    echo "$sorted_bam"
}

#===============================================================================
# Function to index BAM file
#===============================================================================

index_bam_file() {
    local sorted_bam="$1"
    
    # Extract sample name from filename
    local sample_name=$(basename "$sorted_bam" .sorted.bam)
    
    print_info "Indexing sorted BAM: $sample_name"
    
    # Create BAM index
    samtools index -@ "$SAMTOOLS_THREADS" "$sorted_bam" || \
        error_exit "BAM indexing failed for $sample_name"
    
    print_success "BAM indexing complete: $sample_name"
    
    # Display BAM file statistics
    local total_reads=$(samtools flagstat "$sorted_bam" | head -1 | awk '{print $1}')
    local mapped_reads=$(samtools flagstat "$sorted_bam" | grep "mapped" | head -1 | awk '{print $1}')
    
    echo "  - Total reads: $total_reads"
    echo "  - Mapped reads: $mapped_reads"
}

#===============================================================================
# Function to run MultiQC on alignment results
#===============================================================================

run_multiqc_alignment() {
    local align_dir="$1"
    local output_dir="$2"
    
    print_info "Aggregating alignment statistics with MultiQC..."
    
    multiqc "$align_dir" \
        -o "$output_dir" \
        --force \
        --title "SAM to BAM Processing Report" || \
        error_exit "MultiQC aggregation failed."
    
    print_success "MultiQC report generated."
}

#===============================================================================
# Main execution
#===============================================================================

echo ""
print_info "Starting SAM to BAM processing pipeline..."
echo ""

# Step 1: Convert SAM to BAM
print_info "Step 1: Converting SAM files to BAM format..."
echo ""

for sam_file in "$ALIGNMENT_DIR"/*.sam; do
    if [[ -f "$sam_file" ]]; then
        convert_sam_to_bam "$sam_file" "$ALIGNMENT_DIR"
        echo ""
    fi
done

# Step 2: Sort BAM files
print_info "Step 2: Sorting BAM files..."
echo ""

for bam_file in "$ALIGNMENT_DIR"/*.bam; do
    if [[ -f "$bam_file" ]]; then
        sorted_bam=$(sort_bam_file "$bam_file" "$ALIGNMENT_DIR")
        echo ""
    fi
done

# Step 3: Index sorted BAM files
print_info "Step 3: Indexing sorted BAM files..."
echo ""

for sorted_bam in "$ALIGNMENT_DIR"/*.sorted.bam; do
    if [[ -f "$sorted_bam" ]]; then
        index_bam_file "$sorted_bam"
        echo ""
    fi
done

#===============================================================================
# Final summary
#===============================================================================

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SAM to BAM processing completed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Summary:"
echo "  Input directory: $ALIGNMENT_DIR"
echo "  Samples processed: $SAM_COUNT"
echo "  Output format: Sorted and indexed BAM"
echo ""
echo "Generated sorted BAM files:"
ls -lh "$ALIGNMENT_DIR"/*.sorted.bam 2>/dev/null | awk '{print "  " $9}' || echo "  No sorted BAM files found"
echo ""
echo "Generated BAM index files:"
ls -lh "$ALIGNMENT_DIR"/*.sorted.bam.bai 2>/dev/null | awk '{print "  " $9}' || echo "  No index files found"
echo ""
