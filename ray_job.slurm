#!/bin/bash
#SBATCH --job-name=verl-dsv3-dapo-671b-megatron
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=96
#SBATCH --time=12:00:00
#SBATCH --output=/traindata/%u/runs/verl/slurm-%j.out
#SBATCH --error=/traindata/%u/runs/verl/slurm-%j.err

# Load any necessary modules
# module load python/3.10
# module load ray/2.10.0

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
    -w $head_node \
    ray start --head --node-ip-address=$head_node_ip --port=6379 --block &

# Allow some time for the head node to start
sleep 10

# Start Ray worker nodes
for ((i=1; i<${#nodes_array[@]}; i++)); do
    node=${nodes_array[$i]}
    srun \
        --container-image /traindata/enroot_images/verl_dsv3.sqsh \
        --container-mounts "/traindata:/traindata" \
        --nodes=1 \
        --ntasks=1 \
        -w $node \
        ray start --address=$head_node_ip:6379 --block &
    sleep 5
done

# Run the Python script
srun \
    --container-image /traindata/enroot_images/verl_dsv3.sqsh \
    --container-mounts "/traindata:/traindata" \
    --export=ALL \
    --nodes=1 \
    --ntasks=1 \
    -w $head_node \
    bash -c \
    "
    cd /traindata/$USER/verl-pplx
    recipe/dapo/test_dapo_dspk_671b_megatron.sh
    "
