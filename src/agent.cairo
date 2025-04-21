use starknet::ContractAddress;

#[starknet::interface]
pub trait IAgent<TContractState> {
    fn factory(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
mod Agent {
    // Imports
    use openzeppelin_access::ownable::OwnableComponent;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address};

    // Component Declarations
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    // External Mixins
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;

    // Internal Mixins
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    // Storage
    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        _factory: ContractAddress,
    }

    // Events
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    // Constructor
    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.ownable.initializer(owner);

        self._factory.write(get_caller_address());
    }

    // Public Functions
    #[abi(embed_v0)]
    impl AgentImpl of super::IAgent<ContractState> {
        fn factory(self: @ContractState) -> ContractAddress {
            return self._factory.read();
        }
    }

    // Internal Functions
    #[generate_trait]
    impl AgentInternalImpl of IAgentInternalImpl {}
}
