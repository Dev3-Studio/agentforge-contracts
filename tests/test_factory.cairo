use starknet::{ClassHash, ContractAddress};
use snforge_std::{ContractClassTrait, DeclareResultTrait, ContractClass, declare, start_cheat_caller_address_global, stop_cheat_caller_address_global};

pub fn declare_and_deploy_udc() -> (ContractClass, ClassHash, ContractAddress) {
    let contract = declare("UniversalDeployer").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![]).unwrap();
    return (*contract, *contract.class_hash , contract_address);
}

fn deploy_factory() -> ContractAddress {
    let factory_class = declare("Factory").unwrap().contract_class();
    let owner_address: ContractAddress = 'owner'.try_into().unwrap();
    let signer_address: ContractAddress = 'signer'.try_into().unwrap();
    let agent_class = declare("Agent").unwrap().contract_class();

    let (_, _, udc_address)  = declare_and_deploy_udc();

    let mut calldata: Array<felt252> = array![
        signer_address.into(),
        udc_address.into(),
        (*agent_class).class_hash.into(),
    ];


    println!("Calldata: {:?}", calldata);

    start_cheat_caller_address_global(owner_address);

    let (contract_address, _) = factory_class.deploy(@calldata).unwrap();

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

