#!/usr/bin/env bash
case_name=$1

echo "downloading case ${case_name}..."
wget -q "${STORAGE_ENDPOINT}/ansys-mechanical-benchmarks/BENCH_V180_LINUX.tgz?${SAS_KEY}" -O - | tar -xz

source /opt/intel/impi/*/bin64/mpivars.sh

if [ "$INTERCONNECT" == "ib" ]; then
    export I_MPI_FABRICS=shm:dapl
    export I_MPI_DAPL_PROVIDER=ofa-v2-ib0
    export I_MPI_DYNAMIC_CONNECTION=0
    export I_MPI_FALLBACK_DEVICE=0
    export FLUENT_BENCH_OPTIONS="-pib.dapl"
elif [ "$INTERCONNECT" == "sriov" ]; then
    export I_MPI_FABRICS=shm:ofa
    export I_MPI_FALLBACK_DEVICE=0
    export FLUENT_BENCH_OPTIONS="-pinfiniband"
else
    export I_MPI_FABRICS=shm:tcp
fi
export VERSION=192
export PATH=/opt/ansys_inc/v$VERSION/ansys/bin:$PATH
export ANSYSLMD_LICENSE_FILE=1055@${LICENSE_SERVER}

OUTPUT_FILE=${case_name}-${CORES}.out
echo ${MPI_HOSTLIST} | sed "s/,/:${PPN}:/g" | sed "s/$/:${PPN}/" > ansysmech-hostlist

# note ansys takes number of cores from host list, not -np
ansys$VERSION -b -dis -mpi intelmpi -ssh -machines `cat ansysmech-hostlist` -i ${case_name}.dat -o ${OUTPUT_FILE} 


# extract telemetry
if [ -f "${OUTPUT_FILE}" ]; then
    compute_time=$(grep "Elapsed time spent computing solution" ${OUTPUT_FILE}  | awk '{print $7}')
    total_cpu_time=$(grep "Total CPU time summed for all threads" ${OUTPUT_FILE}  | awk '{print $9}')
       
    cat <<EOF >$APPLICATION.json
    {
    "version": "$VERSION",
    "model": "$case_name",
    "compute_time": $compute_time,
    "total_cpu_time": $total_cpu_time    
    }
EOF
fi
