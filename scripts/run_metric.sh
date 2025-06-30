#!/bin/bash
# Read dwi from inputs/ and write metric to outputs/
# Metric is read from environment variable METRIC

set -e

echo "Running BeyondFA baseline..."
echo "Listing /input..."
ls /input
echo "Listing /input/*..."
ls /input/*
echo "Listing /output..."
ls /output/

# Define metric
METRICS=("fa" "md" "ad" "rd")
NR_POINTS=7

# Find all dwi.mha files in /input
dwi_mha_files=$(find /input/images/dwi-4d-brain-mri -name "*.mha")

for dwi_mha_file in $dwi_mha_files; do
    # Set up file names
    json_file="/input/dwi-4d-acquisition-metadata.json"
    [[ ! -f $json_file ]] && { echo "Missing $json_file"; exit 1; }

    basename=$(basename $dwi_mha_file .mha)
    bval_path="/tmp/${basename}.bval"
    bvec_path="/tmp/${basename}.bvec"
    nifti_file="/tmp/${basename}.nii.gz"
    output_name="/output/features-128.json"

    # Convert dwi.mha to nii.gz
    echo "Converting $dwi_mha_file to $nifti_file..."
    python convert_mha_to_nifti.py $dwi_mha_file $nifti_file

    # Convert json to bval and bvec
    echo "Converting $json_file to $bval_path and $bvec_path..."
    python convert_json_to_bvalbvec.py $json_file $bval_path $bvec_path

    # Define output directory
    output_dir="/tmp/tractseg_output"
    mkdir -p $output_dir

    # Create mask, response, FODs, and peaks
    tractseg_dir="${output_dir}/${basename}/tractseg"
    mkdir -p $tractseg_dir

    echo "Creating mask, response, FODs, and peaks..."
    dwi2mask $nifti_file $tractseg_dir/nodif_brain_mask.nii.gz \
        -fslgrad $bvec_path $bval_path
    dwi2response fa $nifti_file $tractseg_dir/response.txt \
        -fslgrad $bvec_path $bval_path
    dwi2fod csd $nifti_file $tractseg_dir/response.txt $tractseg_dir/WM_FODs.nii.gz \
        -mask $tractseg_dir/nodif_brain_mask.nii.gz \
        -fslgrad $bvec_path $bval_path
    sh2peaks $tractseg_dir/WM_FODs.nii.gz $tractseg_dir/peaks.nii.gz \
        -mask $tractseg_dir/nodif_brain_mask.nii.gz -fast

    # Run TractSeg
    echo "Running TractSeg..."
    TractSeg  -i "$tractseg_dir/peaks.nii.gz" --output_type tract_segmentation \
            -o "$tractseg_dir" \
            --bvals $bval_path --bvecs $bvec_path \
            --keep_intermediate_files \
            --brain_mask "$tractseg_dir/nodif_brain_mask.nii.gz"

    TractSeg  -i "$tractseg_dir/peaks.nii.gz" --output_type endings_segmentation \
            -o "$tractseg_dir" \
            --bvals $bval_path --bvecs $bvec_path \
            --keep_intermediate_files \
            --brain_mask "$tractseg_dir/nodif_brain_mask.nii.gz"

    TractSeg  -i "$tractseg_dir/peaks.nii.gz" --output_type TOM \
            -o "$tractseg_dir" \
            --bvals $bval_path --bvecs $bvec_path \
            --keep_intermediate_files \
            --brain_mask "$tractseg_dir/nodif_brain_mask.nii.gz"

    Tracking  -i "$tractseg_dir/peaks.nii.gz" -o "$tractseg_dir" --tracking_format tck \
            --bundles CG_left,CG_right,UF_left,UF_right,ILF_left,ILF_right

    echo "Calculating DTI metrics..."
    metric_dir="${output_dir}/${basename}/metric"
    mkdir -p $metric_dir
    scil_dti_metrics.py \
        --fa  $metric_dir/fa.nii.gz  \
        --md  $metric_dir/md.nii.gz  \
        --ad  $metric_dir/ad.nii.gz  \
        --rd  $metric_dir/rd.nii.gz  \
        --not_all \
        --mask $tractseg_dir/nodif_brain_mask.nii.gz \
        $nifti_file $bval_path $bvec_path -f

    fslmaths $metric_dir/md.nii.gz -mul 1000 $metric_dir/md.nii.gz
    fslmaths $metric_dir/ad.nii.gz -mul 1000 $metric_dir/ad.nii.gz
    fslmaths $metric_dir/rd.nii.gz -mul 1000 $metric_dir/rd.nii.gz

    echo "Sampling scalar maps along bundles..."
    profile_dir="${output_dir}/${basename}/profiles"
    mkdir -p $profile_dir
    for m in "${METRICS[@]}"; do
        scalar_img="${metric_dir}/${m}.nii.gz"
        csv_out="${profile_dir}/${m}_profiles.csv"

        Tractometry \
            -i  "$tractseg_dir/TOM_trackings" \
            -o  "$csv_out" \
            -e  "$tractseg_dir/endings_segmentations" \
            -s  "$scalar_img" \
            --nr_points "$NR_POINTS" \
            --tracking_format tck
    done

    echo "Merging profiles into 128-D feature..."
    python merge_features.py "$profile_dir" "$output_name"
    echo "Feature vector saved to $output_name"
done
