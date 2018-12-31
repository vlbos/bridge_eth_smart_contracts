pragma solidity 0.5.0;


contract Relay {

    uint constant TIMESTAMP_BYTES               = 4;
    uint constant PRODUCER_BYTES                = 8;
    uint constant CONFIRMED_BYTES               = 2;
    uint constant PREVIOUS_BYTES                = 32;
    uint constant TX_MROOT_BYTES                = 32;
    uint constant ACTION_MROOT_BYTES            = 32;
    uint constant SCHEDULE_BYTES                = 4;
    uint constant HAVE_NEW_PRODUCERS_BYTES      = 1;
    uint constant PRODUCERS_VERSION_BYTES       = 4;
    uint constant PRODUCERS_NAME_BYTES          = 8;
    uint constant PRODUCERS_AMOUNT_BYTES        = 1;
    uint constant PRODUCERS_KEY_HIGH_BYTES      = 32;

    function sliceBytes(bytes memory bs, uint start, uint size) internal pure returns (uint)
    {
        require(bs.length >= start + size, "slicing out of range");
        uint x;
        assembly {
            x := mload(add(bs, add(size, start)))
        }
        return x;
    }

    function parseFixedFields0(bytes memory blockHeader)
        internal
        pure
        returns (uint32 ts, uint64 producer, uint16 confirmed, uint previous, uint tx_mroot)
    {

        uint offset = 0;

        ts = (uint32)(sliceBytes(blockHeader, offset, TIMESTAMP_BYTES));
        offset = offset + TIMESTAMP_BYTES;

        producer = (uint64)(sliceBytes(blockHeader, offset, PRODUCER_BYTES));
        offset = offset + PRODUCER_BYTES;

        confirmed = (uint16)(sliceBytes(blockHeader, offset, CONFIRMED_BYTES));
        offset = offset + CONFIRMED_BYTES;

        previous = (uint256)(sliceBytes(blockHeader, offset, PREVIOUS_BYTES));
        offset = offset + PREVIOUS_BYTES;

        tx_mroot = (uint256)(sliceBytes(blockHeader, offset, TX_MROOT_BYTES));
        offset = offset + TX_MROOT_BYTES;
    }

    function parseFixedFields1(bytes memory blockHeader)
        internal
        pure
        returns (uint32 schedule, uint action_mroot, uint8 have_new_producers)
    {

        uint offset = 78;

        schedule = (uint32)(sliceBytes(blockHeader, offset, SCHEDULE_BYTES));
        offset = offset + SCHEDULE_BYTES;

        action_mroot = (uint256)(sliceBytes(blockHeader, offset, ACTION_MROOT_BYTES));
        offset = offset + ACTION_MROOT_BYTES;

        have_new_producers = (uint8)(sliceBytes(blockHeader, offset, HAVE_NEW_PRODUCERS_BYTES));
        offset = offset + HAVE_NEW_PRODUCERS_BYTES;
    }

    function parseNonFixedFields(bytes memory blockHeader)
        internal
        pure
        returns (uint32 version, uint8 amount, uint64[21] memory producerNames, bytes32[21] memory producerKeyHighChunk)
    {

        uint offset = 115;

        version = (uint32)(sliceBytes(blockHeader, offset, PRODUCERS_VERSION_BYTES));
        offset = offset + PRODUCERS_VERSION_BYTES;

        amount = (uint8)(sliceBytes(blockHeader, offset, PRODUCERS_AMOUNT_BYTES));
        offset = offset + PRODUCERS_AMOUNT_BYTES;

        for (uint i = 0; i < amount; i++) {
            producerNames[i] = (uint64)(sliceBytes(blockHeader, offset, PRODUCERS_NAME_BYTES));
            offset = offset + PRODUCERS_NAME_BYTES;

            offset = offset + 1; // skip 1 zeroed bytes
            offset = offset + 1; // skip first byte of the key

            producerKeyHighChunk[i] = (bytes32)(sliceBytes(blockHeader, offset, PRODUCERS_KEY_HIGH_BYTES));
            offset = offset + PRODUCERS_KEY_HIGH_BYTES;
        }
    } 

    function parseHeader(bytes calldata blockHeader)
        external
        pure
        returns (
            uint32 timestamp,
            uint64 producer,
            uint16 confirmed,
            uint previous,
            uint tx_mroot,
            uint32 schedule,
            uint action_mroot,
            uint32 version,
            uint8 amount,
            uint64[21] memory producerNames,
            bytes32[21] memory producerKeyHighChunk // TODO: this should be 33 bytes!!!
        )
    {
        /* expected sizes 4, 8, 2, 32, 32, 32, 4, 1, 1 */

        (timestamp, producer, confirmed, previous, tx_mroot) = parseFixedFields0(blockHeader);
        uint8 have_new_producers;
        (schedule, action_mroot, have_new_producers) = parseFixedFields1(blockHeader);

        if(have_new_producers != 0 ) {
            
            (version, amount, producerNames, producerKeyHighChunk) = parseNonFixedFields(blockHeader);
        }
    }

    function verifyBlockSig(
        bytes calldata blockHeader,             // from user
        bytes32 blockMerkleHash,                // from user
        bytes calldata pendingSchedule,         // from user 
        uint8 sigV,                             // from user
        bytes32 sigR,                           // from user
        bytes32 sigS,                           // from user
        bytes32[] calldata claimedSignerPubKey, // from user
        bytes32 storedCompressedPubKey          // from storage (we maintain current schedule keys)
    )
        external
        pure
        returns (bool) 
    {
        bytes32 pairHash = sha256(abi.encodePacked(sha256(blockHeader), blockMerkleHash));
        bytes32 pendingScheduleHash = sha256(pendingSchedule);
        bytes32 finalHash = sha256(abi.encodePacked(pairHash, pendingScheduleHash));
        address calcAddress = ecrecover(finalHash, sigV, sigR, sigS);
        address claimedSignerAddress = address(
            (uint)(keccak256(abi.encodePacked(claimedSignerPubKey[0], claimedSignerPubKey[1]))) & (2**(8*21)-1)
        );

        return (
            (claimedSignerPubKey[0] == storedCompressedPubKey) && // signer is part of current schedule
            (calcAddress == claimedSignerAddress)                 // signer signed the given block data 
        );
    }
}