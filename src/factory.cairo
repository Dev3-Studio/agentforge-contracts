use starknet::ContractAddress;

#[starknet::interface]
pub trait IFactory<TContractState> {
    fn create_agent(ref self: TContractState, name: ByteArray, accepted_tokens: Array<ContractAddress>) -> ContractAddress;
    fn set_signer(ref self: TContractState, signer: ContractAddress);
    fn get_signer(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
pub mod Factory {
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin_utils::serde::SerializedAppend;
    use starknet::{ClassHash, get_caller_address, get_contract_address, ContractAddress};
    use openzeppelin_utils::interfaces::{
        IUniversalDeployerDispatcher, IUniversalDeployerDispatcherTrait,
    };
    use starknet::storage::{StoragePointerWriteAccess, StoragePointerReadAccess};

    // Component Declarations
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    // External Mixins
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;

    // Internal Mixins
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        agents: Array<ContractAddress>,
        universal_deployer_address: ContractAddress,
        agent_class_hash: ClassHash,
        signer: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        AgentCreated: AgentCreated,
        SignerUpdated: SignerUpdated,
    }

    #[derive(Drop, starknet::Event)]
    pub struct AgentCreated {
        #[key]
        pub address: ContractAddress,
        #[key]
        pub name: ByteArray,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SignerUpdated {
        #[key]
        pub signer: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        signer: ContractAddress,
        universal_deployer_address: ContractAddress,
        agent_class_hash: ClassHash,
    ) {
        self.ownable.initializer(get_caller_address());
        self.signer.write(signer);
        self.universal_deployer_address.write(universal_deployer_address);
        self.agent_class_hash.write(agent_class_hash);
    }


    #[abi(embed_v0)]
    impl FactoryImpl of super::IFactory<ContractState> {

        fn create_agent(ref self: ContractState, name: ByteArray, accepted_tokens: Array<ContractAddress>) -> ContractAddress {
            self.ownable.assert_only_owner();

            let dispatcher = IUniversalDeployerDispatcher {
                contract_address: self.universal_deployer_address.read(),
            };

            let mut agent_calldata: Array<felt252> = array![];
            let factory_address: felt252 = get_contract_address().into();
            agent_calldata.append_serde(accepted_tokens);
            agent_calldata.append_serde(name.clone().into());
            agent_calldata.append_serde(factory_address);

            let agent_contract_address = dispatcher
                .deploy_contract(
                    self.agent_class_hash.read(),
                    // salt
                    123456,
                    false,
                    agent_calldata.span(),
            );

            self.emit(
                AgentCreated { address: agent_contract_address, name: name },
            );

            return agent_contract_address;
        }

        fn set_signer(ref self: ContractState, signer: ContractAddress){
            self.ownable.assert_only_owner();

            self.signer.write(signer);
            self.emit(
                SignerUpdated { signer: signer },
            );
        }

        fn get_signer(self: @ContractState) -> ContractAddress {
            return self.signer.read();
        }


    }

}