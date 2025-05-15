use starknet::ContractAddress;

#[starknet::interface]
pub trait IAgent<TContractState> {
    fn factory(self: @TContractState) -> ContractAddress;
    fn update_accepted_tokens(
        self: @TContractState,
        accepted_tokens: Map<felt252, ContractAddress>,
    );
    fn execute(
        self: @TContractState,
        signature: felt252,
    );
}

#[starknet::contract]
mod Agent {
    // Imports
    use openzeppelin_access::ownable::OwnableComponent;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address};
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::secp256_trait::{Signature};

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
        accepted_tokens: Map<felt252, ContractAddress>,
        nonces: Map<ContractAddress, felt252>,
        _factory: ContractAddress,
        _signer: ContractAddress,
    }

    // Events
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        ExecuteSuccess: ExecuteSuccess,
    }

    #[derive(Drop, starknet::Event)]
    struct ExecuteSuccess {
        #[key]
        caller: ContractAddress,
        token: ContractAddress,
        amount: felt252,
        nonce: felt252,
    }

    // Constructor
    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, signer: ContractAddress, accepted_tokens: Map<felt252, ContractAddress>) {
        self.ownable.initializer(owner);

        self._factory.write(get_caller_address());
        self._signer.write(signer);
        self.accepted_tokens.write(accepted_tokens);
    }

    // Public Functions
    #[abi(embed_v0)]
    impl AgentImpl of super::IAgent<ContractState> {
        fn factory(self: @ContractState) -> ContractAddress {
            return self._factory.read();
        }

        fn update_accepted_tokens(
            self: @ContractState,
            accepted_tokens: Map<felt252, ContractAddress>,
        ) {
            self.ownable.assert_only_owner();
            self.accepted_tokens.write(accepted_tokens);
        }

        // ensure signature is from signer and deduct signed amount of tokens from the sender
        fn execute(
            self: @ContractState,
            amount: felt252,
            token: ContractAddress,
            signature: Signature,
        ) {
            let signer = self._signer.read();
            let caller = get_caller_address();
            let nonce = self.nonces.read(caller);

            // Build hash for calling `is_valid_signature`
            let message = Message { amount, token, nonce };
            let hash = message.get_message_hash(signer);

            let is_valid_signature_felt = ISRC6Dispatcher { contract_address: signer }
                .is_valid_signature(hash, signature);

            // Check if the signature is valid
            let is_valid_signature = is_valid_signature_felt == starknet::VALIDATED
                || is_valid_signature_felt == 1;
            assert(is_valid_signature, 'Invalid signature');


            // Check if the token is accepted
            let accepted_tokens = self.accepted_tokens.read();
            if !accepted_tokens.contains_key(token) {
                panic("Token not accepted");
            }

            // Check if the amount is valid
            if amount <= 0 {
                panic("Invalid amount");
            }

            // Transfer the tokens from the sender to the contract
            let erc20dispatcher = IERC20Dispatcher {contract_address: token};
            erc20dispatcher.transfer_from(get_caller_address(), get_contract_address(), amount);

            // Emit event
            self.emit(ExecuteSuccess {
                caller: caller,
                token: token,
                amount: amount,
                nonce: nonce,
            });

            // Increment the nonce
            self.nonces.write(caller, nonce + 1);
        }
    }

    // Internal Functions
    #[generate_trait]
    impl AgentInternalImpl of IAgentInternalImpl {}
}
