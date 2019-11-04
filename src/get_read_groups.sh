#!/bin/bash

# Matthew Wyczalkowski <m.wyczalkowski@wustl.edu>
# https://dinglab.wustl.edu/

read -r -d '' USAGE <<'EOF'
Query GDC to obtain read groups associated with aliquots

Usage:
  get_read_groups.sh [options] aliquots.dat

aliquots.dat is a file with aliquot information as generated by get_aliquots.sh
Writes the following columns for each read group
    * case
    * aliquot submitter id
    * read group submitter id
    * library strategy
    * experiment name
    * target capture kit target region

Options:
-h: Print this help message
-v: Verbose.  May be repeated to get verbose output from queryGDC.sh
-o OUTFN: write results to output file instead of STDOUT.  Will be overwritten if exists

Require GDC_TOKEN environment variable to be defined with path to gdc-user-token.*.txt file
EOF

QUERYGDC="src/queryGDC.sh"
# http://wiki.bash-hackers.org/howto/getopts_tutorial
while getopts ":hvo:" opt; do
  case $opt in
    h)
      echo "$USAGE"
      exit 0
      ;;
    v)  
      VERBOSE="${VERBOSE}v"
      ;;
    o)  
      OUTFN="$OPTARG"
      if [ -f $OUTFN ]; then
          >&2 echo WARNING: $OUTFN exists.  Deleting
          rm -f $OUTFN
      fi
      ;;
    \?)
      >&2 echo "Invalid option: -$OPTARG"
      echo "$USAGE"
      exit 1
      ;;
    :)
      >&2 echo "Option -$OPTARG requires an argument."
      echo "$USAGE"
      exit 1
      ;;
  esac
done
shift $((OPTIND-1))

if [ "$#" -ne 1 ]; then
    >&2 echo Error: Wrong number of arguments
    echo "$USAGE"
    exit 1
fi
DAT=$1

if [ -z $GDC_TOKEN ]; then
    >&2 echo GDC_TOKEN environment variable not defined.  Quitting.
    exit 1
fi

# Called after running scripts to catch fatal (exit 1) errors
# works with piped calls ( S1 | S2 | S3 > OUT )
function test_exit_status {
    # Evaluate return value for chain of pipes; see https://stackoverflow.com/questions/90418/exit-shell-script-based-on-process-exit-code
    # exit code 137 is fatal error signal 9: http://tldp.org/LDP/abs/html/exitcodes.html

    rcs=${PIPESTATUS[*]};
    for rc in ${rcs}; do
        if [[ $rc != 0 ]]; then
            >&2 echo Fatal error.  Exiting
            exit $rc;
        fi;
    done
}

function read_group_from_aliquot_query {
    ALIQUOT=$1 
    cat <<EOF
    {
        read_group(with_path_to: {type: "aliquot", submitter_id:"$ALIQUOT"}, first:10000)
        {
            submitter_id
            library_strategy
            experiment_name
            target_capture_kit_target_region
        }
    }
EOF
}

if [ $VERBOSE ]; then
    >&2 echo Processing $DAT
fi

while read L; do
#    * case
#    * sample submitter id
#    * sample id
#    * sample type
#    * aliquot submitter id
#    * aliquot id
#    * analyte_type

    CASE=$(echo "$L" | cut -f 1)
    ASID=$(echo "$L" | cut -f 5)
    Q=$(read_group_from_aliquot_query $ASID)
    if [ $VERBOSE ]; then
        >&2 echo QUERY: $Q
        if [ "$VERBOSE" == "vv" ] ; then
            GDC_VERBOSE="-v"
        fi
    fi

    R=$(echo $Q | $QUERYGDC -r $GDC_VERBOSE -)
    test_exit_status

    if [ $VERBOSE ]; then
        >&2 echo RESULT: $R
    fi

    OUTLINE=$(echo $R | jq -r '.data.read_group[] | "\(.submitter_id)\t\(.library_strategy)\t\(.experiment_name)\t\(.target_capture_kit_target_region)"' | sed "s/^/$CASE\t$ASID\t/")
    test_exit_status

    if [ "$OUTLINE" ]; then
        if [ ! -z $OUTFN ]; then
            echo "$OUTLINE" >> $OUTFN
        else
            echo "$OUTLINE"
        fi
    fi

done < $DAT

if [ ! -z $OUTFN ]; then
    >&2 echo Written to $OUTFN
fi
