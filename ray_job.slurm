#!/bin/bash
#SBATCH --job-name=verl-dsv3-dapo-671b-megatron
#SBATCH --nodes=32
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=96
#SBATCH --gpus-per-task=8
#SBATCH --time=12:00:00
#SBATCH --output=/traindata/%u/runs/%j-verl/slurm.out
#SBATCH --error=/traindata/%u/runs/%j-verl/slurm.out

# OUTDIR="/traindata/$USER/runs/$SLURM_JOB_ID-verl"
# mkdir -p ${OUTDIR}

# Get the node names
nodes=$(scontrol show hostnames $SLURM_JOB_NODELIST)
nodes_array=($nodes)

# Head node is the first node in the array
head_node=${nodes_array[0]}
head_node_ip=$(srun --nodes=1 --ntasks=1 -w $head_node hostname --ip-address)
echo "Head node: $head_node $head_node_ip"

# Start the Ray head node
srun \
    --container-image /traindata/enroot_images/verl_dsv3.sqsh \
    --container-mounts "/traindata:/traindata" \
    --nodes=1 \
    --ntasks=1 \
    --gres=gpu:8 \
    -w $head_node \
    ray start --head --node-ip-address 0.0.0.0 --port=6379 --num-cpus 96 --num-gpus 8 --block &

# Allow some time for the head node to start
sleep 10

# Start Ray worker nodes on node 1 to N-2 (excluding the last node)
# Last node is reserved for running the training script
for ((i=1; i<$((${#nodes_array[@]} - 1)); i++)); do
    node=${nodes_array[$i]}
    echo "Starting Ray worker node $node"
    srun \
        --container-image /traindata/enroot_images/verl_dsv3.sqsh \
        --container-mounts "/traindata:/traindata" \
        --nodes=1 \
        --ntasks=1 \
        --gres=gpu:8 \
        -w $node \
        ray start --address $head_node_ip:6379 --num-cpus 96 --num-gpus 8 --block &
    sleep 1
done

echo "Waiting for all nodes to start and join the cluster..."
sleep 30

# Get the last node for running the training script
echo "Running the training script on the last worker node"
node=${nodes_array[-1]}
srun \
    --container-image /traindata/enroot_images/verl_dsv3.sqsh \
    --container-mounts "/traindata:/traindata" \
    --export=ALL \
    --nodes=1 \
    --ntasks=1 \
    --overlap \
    -w $node \
    bash -c \
    "
    echo \"training script is running on $(hostname --ip-address)\"
    # Connect to the Ray cluster from the training node
    ray start --address $head_node_ip:6379 --num-cpus 96 --num-gpus 8 --block &
    sleep 10
    ray status
    cd /traindata/$USER/verl-pplx
    # sleep infinity
    bash recipe/dapo/test_dapo_dspk_671b_megatron.sh
    "
