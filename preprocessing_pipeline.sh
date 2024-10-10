# our general preprocessing pipeline as of October 2024, built by Tim Jordan (now at Emory). I condensed a few scripts into one
# and eliminated a few checking/prepping scripts, but this still captures the actual preprocessing steps (I think) --np

#hoffman2 resource request
#$ -pe shared 2
#$ -l h_rt=24:00:00,h_data=32G

# load modules
. /u/local/Modules/default/init/modules.sh
module use /u/project/CCN/apps/modulefiles
module use /u/project/CCN/apps/fsl/6.0.7.1/

module load fsl/6.0.7.1
module load R/4.0.2
module load fix
export R_LIBS=/u/project/CCN/apps/R_libs/rh7/4.0.2

# Define directories
DATADIR=/u/project/petersen/data/tms/bids
DERIVATIVES=$DATADIR/derivatives/FSLpipeline
PREPROC_DIR=$DERIVATIVES/Preproc.feat

# List of participants (can be changed to any participant list)
PARTICIPANT_LIST=$DATADIR/scripts/FSLpipeline/Preproc_participants.txt

# Loop through participants
while IFS= read subs; do
    echo "Processing participant: $subs"
    SUB_DIR=$DERIVATIVES/$subs

    # Create directories if they don't exist
    mkdir -p $SUB_DIR/PreFSL

    ### Step 1: T1 Preprocessing with fsl_anat ###
    echo "Running fsl_anat for T1-weighted image preprocessing..."
    fsl_anat -i $DATADIR/sub-${subs}/anat/sub-${subs}_T1w.nii.gz -o $SUB_DIR/PreFSL/sub-${subs}
    
    ### Step 2: Fieldmap Correction with topup (if field maps are available) ###
    if [ -f "$DATADIR/sub-${subs}/fmap/sub-${subs}_dir-AP_epi.nii.gz" ]; then
        echo "Running topup for fieldmap correction..."
        fslmerge -t $SUB_DIR/PreFSL/sub-${subs}_epi.nii.gz \
            $DATADIR/sub-${subs}/fmap/sub-${subs}_dir-AP_epi.nii.gz \
            $DATADIR/sub-${subs}/fmap/sub-${subs}_dir-PA_epi.nii.gz

        topup --imain=$SUB_DIR/PreFSL/sub-${subs}_epi.nii.gz \
            --datain=$DATADIR/scripts/FSLpipeline/my_acq_param.txt \
            --config=b02b0.cnf \
            --fout=$SUB_DIR/PreFSL/sub-${subs}_fieldmaphz.nii.gz \
            --iout=$SUB_DIR/PreFSL/sub-${subs}_unwarped_fieldmap.nii.gz
    else
        echo "Fieldmaps not available for participant $subs. Skipping topup."
    fi

    ### Step 3: FEAT Processing ###
    # Copy the FEAT model template and customize it for the current participant
    cp /path/to/templates/feat_template.fsf ./sub-${subs}_FSLpipeline.fsf
    sed -i 's/SUBJECT_ID/'${subs}'/g' ./sub-${subs}_FSLpipeline.fsf

    # Run FEAT with the customized template
    feat ./sub-${subs}_FSLpipeline.fsf

    echo "Running FEAT model for preprocessing (slice timing, motion correction, etc.)..."
    feat $DATADIR/scripts/FSLpipeline/Designs/sub-${subs}_FSLpipeline.fsf

    ### Step 4: ICA-based Denoising with FIX ###
    echo "Running FIX for ICA-based denoising..."
    /u/project/CCN/apps/fix/1.065/fix -f $SUB_DIR/PreFSL/sub-${subs}.feat

    # Check for errors
    grep -Rw $SUB_DIR/PreFSL/sub-${subs}.feat/fix/logMatlab.txt -e 'Error' || echo "FIX completed successfully for $subs."

    echo "Finished processing participant: $subs"
done < $PARTICIPANT_LIST


