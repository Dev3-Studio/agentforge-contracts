use starknet::ContractAddress;
use agentforge::agent::{
    IAgentDispatcher, IAgentDispatcherTrait,
};
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address_global, stop_cheat_caller_address_global};
use openzeppelin_utils::serde::SerializedAppend;

fn deploy_agent() -> ContractAddress {
    let agent_name: felt252 = 'AgentForge_Agent'.try_into().unwrap();
    let agent_class = declare("Agent").unwrap().contract_class();
    let owner_address: ContractAddress = 'owner'.try_into().unwrap();
    let signer_address: ContractAddress = 'signer'.try_into().unwrap();
    let accepted_tokens: Array<felt252> = array![
        'token1'.try_into().unwrap(),
    ];

    let mut calldata: Array<felt252> = array![
        agent_name.into(),
        owner_address.into(),
        signer_address.into(),
    ];

    calldata.append_serde(accepted_tokens);

    println!("Calldata: {:?}", calldata);

    start_cheat_caller_address_global(owner_address);

    let (contract_address, _) = agent_class.deploy(@calldata).unwrap();

    stop_cheat_caller_address_global();
//    let contract_address = match result {
//        Ok((contract_address, _)) => {
//            println!("Agent deployed at: {:?}", contract_address);
//            contract_address;
//       },
//       Err(e) => {
//           println!("Error deploying agent: {:?}", e);
//           panic!("Failed to deploy agent");
//       }
//   };

    return contract_address;
}

#[test]
fn get_selector() {
    let address = deploy_agent();
    let agent = IAgentDispatcher { contract_address: address };

    let selector = agent.get_selector();
    println!("Selector: {:x}", selector);
}