use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin_utils::snip12::{OffchainMessageHash, SNIP12Metadata, StructHash};
use starknet::ContractAddress;

#[starknet::interface]
pub trait IAgent<TContractState> {
    fn factory(self: @TContractState) -> ContractAddress;
    fn add_accepted_tokens(ref self: TContractState, tokens: Array<ContractAddress>);
    fn remove_accepted_token(ref self: TContractState, token: ContractAddress);
    fn execute(
        ref self: TContractState, token: ContractAddress, amount: u256, signature: Array<felt252>,
    );
    // dev function can be removed in production
    fn get_selector(self: @TContractState) -> felt252;
}

const MESSAGE_TYPE_HASH: felt252 =
    0x2d64267ce5f876d7564c5386ed9100d773d3de9ddab561eebfd170d009553b4;


#[derive(Copy, Drop, Hash)]
struct Message {
    caller: ContractAddress,
    amount: u256,
    token: ContractAddress,
    nonce: u256,
}

impl StructHashImpl of StructHash<Message> {
    fn hash_struct(self: @Message) -> felt252 {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(MESSAGE_TYPE_HASH).update_with(*self).finalize()
    }
}


#[starknet::contract]
pub mod Agent {
    // Imports
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin_account::interface::{ISRC6Dispatcher, ISRC6DispatcherTrait};
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use super::{Message, OffchainMessageHash, SNIP12Metadata};
    use starknet::storage::{Map, StoragePointerWriteAccess, StoragePointerReadAccess, StorageMapReadAccess, StorageMapWriteAccess};

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
        name: felt252,
        accepted_tokens: Map<ContractAddress, bool>,
        nonces: Map<ContractAddress, u256>,
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
        amount: u256,
        nonce: u256,
    }

    // Constructor
    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: felt252,
        owner: ContractAddress,
        signer: ContractAddress,
        accepted_tokens: Array<ContractAddress>,
    ) {
        self.ownable.initializer(owner);
        self.name.write(name);
        self._factory.write(get_caller_address());
        self._signer.write(signer);
        self.add_accepted_tokens(accepted_tokens);
    }

    // Required for hash computation
    impl SNIP12MetadataImpl of SNIP12Metadata {
        fn name() -> felt252 {
            'AgentForge_Agent'
        }
        fn version() -> felt252 {
            'v1'
        }
    }



    // Public Functions
    #[abi(embed_v0)]
    impl AgentImpl of super::IAgent<ContractState> {
        fn factory(self: @ContractState) -> ContractAddress {
            return self._factory.read();
        }

        fn add_accepted_tokens(
            ref self: ContractState, tokens: Array<ContractAddress>,
        ) {
            self.ownable.assert_only_owner();

            for i in 0..tokens.len() {
                self.accepted_tokens.write(*tokens.at(i), true);
            }
        }

        fn remove_accepted_token(
            ref self: ContractState, token: ContractAddress,
        ) {
            self.ownable.assert_only_owner();
            self.accepted_tokens.write(token, false);
        }

        fn get_selector(self: @ContractState) -> felt252 {
            let selector = selector!("\"Message\"(\"caller\":\"ContractAddress\",\"amount\":\"u256\",\"token\":\"ContractAddress\",\"nonce\":\"u256\")\"u256\"(\"low\":\"u128\",\"high\":\"u128\")");
            return selector;
        }

        // ensure signature is from signer and deduct signed amount of tokens from the sender
        fn execute(
            ref self: ContractState,
            token: ContractAddress,
            amount: u256,
            signature: Array<felt252>,
        ) {
            let signer = self._signer.read();
            let caller = get_caller_address();
            let nonce = self.nonces.read(caller);

            // Build hash for calling `is_valid_signature`
            let message = Message { caller, amount, token, nonce };
            let hash = message.get_message_hash(signer);

            let is_valid_signature_felt = ISRC6Dispatcher { contract_address: signer }
                .is_valid_signature(hash, signature);

            // Check if the signature is valid
            let is_valid_signature = is_valid_signature_felt == starknet::VALIDATED
                || is_valid_signature_felt == 1;
            assert(is_valid_signature, 'Invalid signature');

            // Check if the token is accepted
            let accepted_tokens = self.accepted_tokens.read(token);
            if !accepted_tokens {
                panic!("Token not accepted");
            }

            // Check if the amount is valid
            if amount < 0 {
                panic!("Invalid amount");
            }

            // Transfer the tokens from the sender to the contract
            let erc20dispatcher = IERC20Dispatcher { contract_address: token };
            erc20dispatcher.transfer_from(get_caller_address(), get_contract_address(), amount);

            // Increment the nonce
            self.nonces.write(caller, nonce + 1);

            // Emit event
            self.emit(
                ExecuteSuccess { caller: caller, token: token, amount: amount, nonce: nonce },
            );
        }
    }

    // Internal Functions
    #[generate_trait]
    impl AgentInternalImpl of IAgentInternalImpl {}
}
