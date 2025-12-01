#!/bin/bash
# Deploy POA Infrastructure to Hoodi

source .env

FOUNDRY_PROFILE=production forge script \
  script/DeployInfrastructure.s.sol:DeployInfrastructure \
  --rpc-url hoodi \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
