#!/bin/bash

# Matthew Wyczalkowski <m.wyczalkowski@wustl.edu>
# https://dinglab.wustl.edu/

read -r -d '' USAGE <<'EOF'
Query GDC to obtain methylation array data associated with aliquots

Usage:
  get_methylation_array.sh [options] aliquot.dat

aliquot.dat is a file with aliquot information as generated by get_aliquot.sh
Writes the following columns for each methylation array
    * case
    * aliquot name
    * name
    * id
    * channel
    * file name
    * file size

Options:
-h: Print this help message
-v: Verbose
-o OUTFN: write results to output file instead of STDOUT.  Will be overwritten if exists

Require GDC_TOKEN environment variable to be defined containing GDC token content
EOF

QUERYGDC="CPTAC3.case.discover/queryGDC"
# http://wiki.bash-hackers.org/howto/getopts_tutorial
while getopts ":hdvo:" opt; do
  case $opt in
    h)
      echo "$USAGE"
      exit 0
      ;;
    d)  # example of binary argument
      >&2 echo "Dry run"
      CMD="echo"
      ;;
    v)  
      VERBOSE="-v"
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

function methylation_array_from_aliquot {
    ALIQUOT=$1 # CPT0206560009
    cat <<EOF
    {
        raw_methylation_array(with_path_to: {type: "aliquot", submitter_id:"$ALIQUOT"}, first:10000)
        {
            submitter_id
            id
            channel
            file_name
            file_size
        }
    }
EOF
}

#OUTD="dat/cases/$CASE"
#mkdir -p $OUTD

#DAT="dat/cases/$CASE/sample_from_case.$CASE.dat"
#OUT="$OUTD/read_group_from_case.$CASE.dat"
#rm -f $OUT

while read L; do
# Columns of input data
#    * case
#    * submitter_id
#    * id
#    * analyte_type

    CASE=$(echo "$L" | cut -f 1)
    ASID=$(echo "$L" | cut -f 2)

    Q=$(methylation_array_from_aliquot $ASID)
    >&2 echo QUERY: $Q

    R=$(echo $Q | $QUERYGDC -r $VERBOSE -)

    OUTLINE=$(echo $R | jq -r '.data.raw_methylation_array[] | "\(.submitter_id)\t\(.id)\t\(.channel)\t\(.file_name)\t\(.file_size)"' | sed "s/^/$CASE\t$ASID\t/" )

    if [ ! -z $OUTFN ]; then
        echo "$OUTLINE" >> $OUTFN
    else
        echo "$OUTLINE"
    fi

done < $DAT

if [ ! -z $OUTFN ]; then
    >&2 echo Written to $OUT
fi
