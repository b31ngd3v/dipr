#!/bin/bash

# Stop any running replica
echo "Stopping any running replica..."
dfx stop

# Start a fresh local replica
echo "Starting local replica..."
dfx start --background --clean

# Create canisters but don't deploy yet
echo "Creating canisters..."
dfx canister create --all

# Build canisters
echo "Building canisters..."
dfx build

# Get user principal for token ownership
USER_PRINCIPAL=$(dfx identity get-principal)
echo "Your principal (token owner): $USER_PRINCIPAL"

# Install token canister with dynamic principal and fee of 100
echo "Installing token canister..."
dfx canister install token --argument='("data:image/png;base64,PLACE_YOUR_BASE64_LOGO_HERE", "IP Token", "IPT", 8, 100000000000, principal "'$USER_PRINCIPAL'", 100)'

# Set fee recipient as the same principal for simplicity
echo "Setting fee recipient..."
dfx canister call token setFeeTo "(principal \"$USER_PRINCIPAL\")"

# Deploy ip_registry
echo "Deploying ip_registry..."
dfx deploy ip_registry

# Deploy internet_identity
echo "Deploying internet_identity..."
dfx deploy internet_identity

# Get canister IDs
TOKEN_ID=$(dfx canister id token)
IP_REGISTRY_ID=$(dfx canister id ip_registry)
II_CANISTER_ID=$(dfx canister id internet_identity)

echo "Token ID: $TOKEN_ID"
echo "IP Registry ID: $IP_REGISTRY_ID"
echo "Internet Identity ID: $II_CANISTER_ID"

# Update canister IDs for cross-canister calls
echo "Updating canister references..."
dfx canister call ip_registry updateTokenCanisterId "(\"$TOKEN_ID\")"
echo "Updated IP Registry token reference"

# Approve tokens for testing
echo "Approving tokens for testing..."
dfx canister call token approve "(principal \"$IP_REGISTRY_ID\", 1000000000)" 
echo "Approved tokens for IP Registry"

# Display token info
echo "Token information:"
dfx canister call token getTokenInfo

# Create a sample IP record
echo "Creating sample IP record..."
IP_ID=$(dfx canister call ip_registry createIpRecord '("Sample Artwork", "A test digital artwork", "QmHashValue123")')
echo "Created IP with ID: $IP_ID"

echo "Setup complete! You can now interact with the canisters."
echo "Try some commands:"
echo "dfx canister call token balanceOf \"(principal \\\"$USER_PRINCIPAL\\\")\"" 
echo "dfx canister call ip_registry stake \"(1, 1000000)\""
echo "dfx canister call ip_registry listAllIPs \"()\"" 