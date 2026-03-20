#!/bin/bash

#===============================================================================
# RNA-Seq Alignment Script using HISAT2
#
# This script performs genome alignment on trimmed FASTQ files using HISAT2.
# It builds a reference genome index (if needed) and aligns reads to the 
# reference, producing SAM files with RNA-seq specific options.
#
# Input:
#   - Reference genome FASTA file
#   - Trimmed paired-end FASTQ files
#
# Output:
#   - HISAT2 reference index
#   - SAM alignment files
#   - HISAT2 alignment summary reports
#
# Requirements:
#   - HISAT2: Fast and sensitive alignment for RNA-Seq data
#   - SAMtools: Sequence Alignment/Map format utilities
#
#===============================================================================

# Source utility functions from utils.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Note: All variables are now defined and exported from main.sh
# Variables available: BASE_DIR, INPUT_DIR, OUTPUT_TRIMMED_DIR, BASE_OUT, REF_DIR,
# HISAT2_INDEX_DIR, ALIGNMENT_DIR, MULTIQC_ALIGN_DIR, HISAT2_THREADS, SEED,
# PHRED_QUALITY, RNA_STRANDNESS, MAX_ALIGNMENTS, REF_FASTA, REF_GTF, REF_INDEX_NAME

# For compatibility with script, define TRIMMED_DIR and SAM_DIR aliases
TRIMMED_DIR="$OUTPUT_TRIMMED_DIR"
SAM_DIR="$ALIGNMENT_DIR"

#===============================================================================
# Validation checks
#===============================================================================

# Check if input directory exists
if [[ ! -d "$INPUT_DIR" ]]; then
    error_exit "Input directory '$INPUT_DIR' not found."
fi

# Check if reference FASTA file exists
if [[ ! -f "$INPUT_DIR/$REF_FASTA" ]]; then
    error_exit "Reference FASTA file '$INPUT_DIR/$REF_FASTA' not found."
fi

# Check if trimmed FASTQ files exist
FASTQ_COUNT=$(ls "$TRIMMED_DIR"/*_1.trimmed.fastq 2>/dev/null | wc -l)
if [[ $FASTQ_COUNT -eq 0 ]]; then
    error_exit "No trimmed FASTQ files found in '$TRIMMED_DIR'. Run trimming script first."
fi

print_info "Found $FASTQ_COUNT trimmed sample pairs to align."

#===============================================================================
# Create output directories
#===============================================================================

print_info "Creating output directories..."
mkdir -p "$REF_DIR" || error_exit "Failed to create directory '$REF_DIR'."
mkdir -p "$HISAT2_INDEX_DIR" || error_exit "Failed to create directory '$HISAT2_INDEX_DIR'."
mkdir -p "$SAM_DIR" || error_exit "Failed to create directory '$SAM_DIR'."
mkdir -p "$MULTIQC_ALIGN_DIR" || error_exit "Failed to create directory '$MULTIQC_ALIGN_DIR'."
print_success "Output directories created."

#===============================================================================
# Function to build HISAT2 reference index
#===============================================================================

build_hisat2_index() {
    local fasta_file="$1"
    local index_dir="$2"
    local index_name="$3"
    
    print_info "Building HISAT2 reference index from: $fasta_file"
    
    # Copy reference file to reference directory
    cp "$fasta_file" "$REF_DIR/" || error_exit "Failed to copy reference FASTA file."
    
    # Extract basename for index naming
    local ref_basename=$(basename "$fasta_file" .fa)
    
    # Build HISAT2 index
    hisat2-build \
        --seed "$SEED" \
        -p "$HISAT2_THREADS" \
        "$REF_DIR/$REF_FASTA" \
        "$index_dir/$index_name" || \
        error_exit "HISAT2 index building failed."
    
    print_success "HISAT2 index built successfully."
}

#===============================================================================
# Function to align paired-end reads
#===============================================================================

align_paired_reads() {
    local read1="$1"
    local read2="$2"
    local index_dir="$3"
    local index_name="$4"
    local output_dir="$5"
    
    # Extract sample name from filename
    local sample_name=$(basename "$read1" _1.trimmed.fastq)
    
    # Define output files
    local sam_file="$output_dir/${sample_name}.sam"
    local summary_file="$output_dir/${sample_name}.hisat2.log"
    
    print_info "Aligning sample: $sample_name"
    
    # Run HISAT2 alignment with RNA-seq specific options
    hisat2 \
        --new-summary \
        --summary-file "$summary_file" \
        --rna-strandness "$RNA_STRANDNESS" \
        --seed "$SEED" \
        --phred"$PHRED_FORMAT" \
        -p "$HISAT2_THREADS" \
        -k "$MAX_ALIGNMENTS" \
        -x "$index_dir/$index_name" \
        -1 "$read1" \
        -2 "$read2" \
        -S "$sam_file" || \
        error_exit "Alignment failed for $sample_name"
    
    print_success "Aligned: $sample_name"
    
    # Extract and display key statistics
    local reads_processed=$(grep "reads processed" "$summary_file" | awk '{print $1}')
    local reads_aligned=$(grep "aligned concordantly exactly 1 time" "$summary_file" | awk '{print $1}')
    
    echo "  - Reads processed: $reads_processed"
    echo "  - Reads aligned: $reads_aligned"
}

#===============================================================================
# Function to run MultiQC on alignment results
#===============================================================================

run_multiqc_alignment() {
    local sam_dir="$1"
    local output_dir="$2"
    
    print_info "Aggregating alignment results with MultiQC..."
    
    multiqc "$sam_dir" \
        -o "$output_dir" \
        --force \
        --title "HISAT2 Alignment Quality Report" || \
        error_exit "MultiQC aggregation failed."
    
    print_success "MultiQC report generated."
}

#===============================================================================
# Main execution
#===============================================================================

echo ""
print_info "Starting RNA-Seq alignment pipeline..."
echo ""

# Build HISAT2 index
build_hisat2_index "$INPUT_DIR/$REF_FASTA" "$HISAT2_INDEX_DIR" "$REF_INDEX_NAME"

echo ""

# Align paired-end samples
print_info "Starting alignment of $FASTQ_COUNT samples..."
echo ""

# Find and align paired FASTQ files
for file in "$TRIMMED_DIR"/*_1.trimmed.fastq; do
    if [[ -f "$file" ]]; then
        # Find corresponding R2 file
        read2_file="${file/_1.trimmed.fastq/_2.trimmed.fastq}"
        if [[ -f "$read2_file" ]]; then
            align_paired_reads "$file" "$read2_file" "$HISAT2_INDEX_DIR" "$REF_INDEX_NAME" "$SAM_DIR"
            echo ""
        else
            error_exit "Corresponding R2 file not found for: $file"
        fi
    fi
done

#===============================================================================
# Final summary
#===============================================================================

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}RNA-Seq alignment pipeline completed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Summary:"
echo "  Reference genome: $REF_FASTA"
echo "  Reference index: $HISAT2_INDEX_DIR/$REF_INDEX_NAME.*"
echo "  Input directory: $TRIMMED_DIR"
echo "  Samples aligned: $FASTQ_COUNT"
echo "  Alignment results: $SAM_DIR"
echo ""
echo "Generated SAM files:"
ls -lh "$SAM_DIR"/*.sam 2>/dev/null | awk '{print "  " $9}' || echo "  No SAM files found"
echo ""
echo "Alignment summaries:"
ls -lh "$SAM_DIR"/*.hisat2.summary 2>/dev/null | awk '{print "  " $9}' || echo "  No summaries found"
echo ""