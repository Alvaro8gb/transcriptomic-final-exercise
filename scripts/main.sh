#!/bin/bash

#===============================================================================
# RNA-Seq Pipeline Main Orchestrator
#
# This script orchestrates the complete RNA-Seq analysis pipeline from
# adapter trimming through gene expression quantification.
#
# Pipeline stages:
#   1. Quality control and adapter trimming (Cutadapt)
#   2. Read alignment (HISAT2)
#   3. SAM to BAM conversion and sorting (SAMtools)
#   4. Gene expression quantification (HTSeq-count)
#
# All parameters and paths are centralized here and passed to subscripts
#
#===============================================================================

set -e  # Exit on error

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

#===============================================================================
# LOGGING SETUP - Output to both console and log file
#===============================================================================

# Get the project root directory (parent of scripts)
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/Apartado1/output"
LOG_FILE="$LOG_DIR/main.log"

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Simple logging function that writes to both console and file
log_output() {
    echo "$@" | tee -a "$LOG_FILE"
}

# Capture all output to log file while still showing on console
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

#===============================================================================
# GLOBAL CONFIGURATION - All variables centralized here
#===============================================================================

# Base directories
export BASE_DIR="Apartado1"
export INPUT_DIR="$BASE_DIR/input"
export BASE_OUT="$BASE_DIR/output"

# Output subdirectories
export OUTPUT_TRIMMED_DIR="$BASE_OUT/trimmed"
export OUTPUT_FASTQC_DIR="$BASE_OUT/fastqc"
export OUTPUT_FASTQC_MULTIQC_DIR="$BASE_OUT/multiqc_reads"
export REF_DIR="$BASE_OUT/reference"
export HISAT2_INDEX_DIR="$BASE_OUT/hisat2_index"
export ALIGNMENT_DIR="$BASE_OUT/alignment"
export MULTIQC_ALIGN_DIR="$BASE_OUT/multiqc"
export HTSEQ_COUNT_DIR="$BASE_OUT/htseq_counts"

#===============================================================================
# CUTADAPT PARAMETERS (Adapter Trimming)
#===============================================================================

export QUALITY_THRESHOLD=20           # Phred quality score threshold
export MIN_LENGTH=20                  # Minimum read length after trimming
export TRIMMING_THREADS=4             # Number of threads for trimming

# Illumina TruSeq adapter sequences
export ADAPTER_R1="AGATCGGAAGAGCACACGTCTGAACTCCAGTCA"    # Read 1 adapter
export ADAPTER_R2="AGATCGGAAGAGCGTCGTGTAGGGAAAGAGTGT"    # Read 2 adapter

#===============================================================================
# FASTQC PARAMETERS (Quality Control)
#===============================================================================

export FASTQC_THREADS=4               # Number of threads for FastQC processing
export FASTQC_MEMORY=250              # Memory allocation for FastQC (MB)

#===============================================================================
# HISAT2 PARAMETERS (Alignment)
#===============================================================================

export HISAT2_THREADS=4               # Number of threads for alignment
export SEED=123                       # Seed for reproducibility
export PHRED_QUALITY="33"             # Phred quality encoding (33 or 64)
export RNA_STRANDNESS="R"             # RNA library strandness (R, F, RF, etc.)
export MAX_ALIGNMENTS=1               # Number of alignment hits to report per read

# Reference genome configuration
export REF_FASTA="Homo_sapiens.GRCh38.dna.chromosome.21.fa"
export REF_GTF="Homo_sapiens.GRCh38.109.chr21.gtf"
export REF_INDEX_NAME="GRCh38.chr21"

#===============================================================================
# SAMTOOLS PARAMETERS (SAM to BAM conversion)
#===============================================================================

export SAMTOOLS_THREADS=4             # Number of threads for SAMtools
export COMPRESSION_LEVEL=9            # BAM compression level (1-9)

#===============================================================================
# HTSEQ-COUNT PARAMETERS (Gene Expression Quantification)
#===============================================================================

export HTSEQ_FORMAT="bam"             # Input file format
export HTSEQ_STRANDED="reverse"       # Strandedness (yes, reverse, or no)
export HTSEQ_MODE="intersection-nonempty"  # Counting mode
export HTSEQ_MIN_QUAL=10              # Minimum alignment quality
export HTSEQ_FEATURE_TYPE="exon"      # Feature type to count
export HTSEQ_IDATTR="gene_id"         # Feature attribute for grouping
export HTSEQ_ADDITIONAL_ATTR="gene_name"  # Additional output attributes
export HTSEQ_THREADS=4                # Number of threads

export ANNOTATION_FILE="$REF_GTF"     # Annotation file path

#===============================================================================
# PRE-FLIGHT CHECKS
#===============================================================================

echo ""
print_info "RNA-Seq Pipeline - Pre-flight Checks"
echo ""

# Check if required directories exist
if [[ ! -d "$INPUT_DIR" ]]; then
    error_exit "Input directory '$INPUT_DIR' not found."
fi

# Check if reference files exist
if [[ ! -f "$INPUT_DIR/$REF_FASTA" ]]; then
    error_exit "Reference FASTA file '$INPUT_DIR/$REF_FASTA' not found."
fi

if [[ ! -f "$INPUT_DIR/$REF_GTF" ]]; then
    error_exit "Reference GTF file '$INPUT_DIR/$REF_GTF' not found."
fi

# Check for input FASTQ files
FASTQ_COUNT=$(ls "$INPUT_DIR"/*_1.fastq 2>/dev/null | wc -l)
if [[ $FASTQ_COUNT -eq 0 ]]; then
    error_exit "No FASTQ files found in '$INPUT_DIR'."
fi

print_success "Input files verified: $FASTQ_COUNT sample pairs found"
echo ""

# Check if required tools are available
for tool in cutadapt hisat2 hisat2-build samtools htseq-count multiqc; do
    command -v "$tool" &> /dev/null || error_exit "$tool is not installed. Please install $tool to continue."
done

print_success "All required tools are available"
echo ""

#===============================================================================
# CREATE OUTPUT DIRECTORY STRUCTURE
#===============================================================================

print_info "Creating output directory structure..."

mkdir -p "$OUTPUT_TRIMMED_DIR" || error_exit "Failed to create directory '$OUTPUT_TRIMMED_DIR'."
mkdir -p "$OUTPUT_FASTQC_DIR" || error_exit "Failed to create directory '$OUTPUT_FASTQC_DIR'."
mkdir -p "$OUTPUT_FASTQC_MULTIQC_DIR" || error_exit "Failed to create directory '$OUTPUT_FASTQC_MULTIQC_DIR'."
mkdir -p "$REF_DIR" || error_exit "Failed to create directory '$REF_DIR'."
mkdir -p "$HISAT2_INDEX_DIR" || error_exit "Failed to create directory '$HISAT2_INDEX_DIR'."
mkdir -p "$ALIGNMENT_DIR" || error_exit "Failed to create directory '$ALIGNMENT_DIR'."
mkdir -p "$MULTIQC_ALIGN_DIR" || error_exit "Failed to create directory '$MULTIQC_ALIGN_DIR'."
mkdir -p "$HTSEQ_COUNT_DIR" || error_exit "Failed to create directory '$HTSEQ_COUNT_DIR'."

print_success "Output directory structure created"
echo ""

#===============================================================================
# PIPELINE EXECUTION
#===============================================================================

print_info "Starting RNA-Seq Analysis Pipeline"
print_info "Pipeline started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# ============================================================================
# STAGE 1: ADAPTER TRIMMING
# ============================================================================

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}STAGE 1: Adapter Trimming (Cutadapt)${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

if bash "$SCRIPT_DIR/trimming_adapters.sh"; then
    print_success "Stage 1 completed: Adapter trimming successful"
else
    error_exit "Stage 1 failed: Adapter trimming pipeline encountered an error"
fi

echo ""

# ============================================================================
# STAGE 2: QUALITY CONTROL OF TRIMMED READS
# ============================================================================

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}STAGE 2: Quality Control - Trimmed Reads (FastQC)${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

if bash "$SCRIPT_DIR/quality_reads.sh"; then
    print_success "Stage 2 completed: Quality control of trimmed reads successful"
else
    error_exit "Stage 2 failed: Quality control of trimmed reads pipeline encountered an error"
fi

echo ""

# ============================================================================
# STAGE 3: READ ALIGNMENT
# ============================================================================

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}STAGE 3: Read Alignment (HISAT2)${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

if bash "$SCRIPT_DIR/aligment.sh"; then
    print_success "Stage 3 completed: Read alignment successful"
else
    error_exit "Stage 3 failed: Read alignment pipeline encountered an error"
fi

echo ""

# ============================================================================
# STAGE 4: SAM TO BAM CONVERSION AND SORTING
# ============================================================================

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}STAGE 4: SAM to BAM Conversion (SAMtools)${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

if bash "$SCRIPT_DIR/sam2bam.sh"; then
    print_success "Stage 4 completed: SAM to BAM conversion successful"
else
    error_exit "Stage 4 failed: SAM to BAM conversion pipeline encountered an error"
fi

echo ""

# ============================================================================
# STAGE 5: GENE EXPRESSION QUANTIFICATION
# ============================================================================

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}STAGE 5: Gene Expression Quantification (HTSeq-count)${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

if bash "$SCRIPT_DIR/htseq_count.sh"; then
    print_success "Stage 5 completed: Gene expression quantification successful"
else
    error_exit "Stage 5 failed: Gene expression quantification pipeline encountered an error"
fi

echo ""

# ============================================================================
# STAGE 6: COMPREHENSIVE QUALITY AGGREGATION WITH MULTIQC
# ============================================================================

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}STAGE 6: MultiQC Aggregation${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

print_info "Aggregating all quality control reports with MultiQC..."
echo ""

# Run MultiQC on all output directories to create comprehensive report
multiqc \
    "$OUTPUT_FASTQC_DIR" \
    "$OUTPUT_TRIMMED_DIR" \
    "$ALIGNMENT_DIR" \
    "$HTSEQ_COUNT_DIR" \
    -o "$MULTIQC_ALIGN_DIR" \
    --title "RNA-Seq Pipeline - Comprehensive Quality Report" \
    2>&1 | tee -a "$LOG_FILE" || true

if [[ -f "$MULTIQC_ALIGN_DIR/multiqc_report.html" ]]; then
    print_success "MultiQC aggregation completed"
    echo "  Report: $MULTIQC_ALIGN_DIR/multiqc_report.html"
else
    print_info "MultiQC report not generated (quality tool data may be missing)"
fi

echo ""

#===============================================================================
# PIPELINE COMPLETION SUMMARY
#===============================================================================

echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}   RNA-Seq Pipeline Completed Successfully!${NC}"
echo -e "${GREEN}======================================================${NC}"
echo ""

echo "Pipeline Execution Summary:"
echo "  Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Project: $BASE_DIR"
echo "  Genome: $REF_FASTA"
echo "  Samples processed: $FASTQ_COUNT"
echo ""

echo "Output Locations:"
echo "  Trimmed reads: $OUTPUT_TRIMMED_DIR"
echo "  Aligned reads (SAM): $ALIGNMENT_DIR"
echo "  Sorted reads (BAM): $ALIGNMENT_DIR"
echo "  Expression counts: $HTSEQ_COUNT_DIR"
echo "  Quality reports: $MULTIQC_ALIGN_DIR/multiqc_report.html"
echo ""

echo "Key Output Files:"
echo "  Trimmed FASTQ files:"
ls -1 "$OUTPUT_TRIMMED_DIR"/*.trimmed.fastq
echo ""
echo "  Sorted BAM files:"
ls -1 "$ALIGNMENT_DIR"/*.sorted.bam 
echo ""
echo "  Expression count files:"
ls -1 "$HTSEQ_COUNT_DIR"/*.htseq  
echo ""

echo -e "${GREEN}======================================================${NC}"
echo ""
