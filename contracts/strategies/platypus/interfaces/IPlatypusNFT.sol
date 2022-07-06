// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "../../../interfaces/IERC721.sol";

interface IPlatypusNFT is IERC721 {
    struct Platypus {
        uint16 level;
        uint16 score;
        // Attributes ( 0 - 9 | D4 D3 D2 D1 C3 C2 C1 B1 B2 A)
        uint8 eyes;
        uint8 mouth;
        uint8 skin;
        uint8 clothes;
        uint8 tail;
        uint8 accessories;
        uint8 bg;
        // Abilities
        // 0 - Speedo
        // 1 - Pudgy
        // 2 - Diligent
        // 3 - Gifted
        // 4 - Hibernate
        uint8[5] ability;
        uint32[5] power;
        uint256 xp;
    }

    /*///////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    function getPrice() external view returns (uint256);

    function availableTotalSupply() external view returns (uint256);

    /*///////////////////////////////////////////////////////////////
        CONTRACT MANAGEMENT OPERATIONS / SALES
    //////////////////////////////////////////////////////////////*/
    function owner() external view returns (address);

    function ownerCandidate() external view returns (address);

    function proposeOwner(address newOwner) external;

    function acceptOwnership() external;

    function cancelOwnerProposal() external;

    function increaseAvailableTotalSupply(uint256 amount) external;

    function changeMintCost(
        uint256 publicCost,
        uint256 wlCost,
        uint256 veCost
    ) external;

    function setSaleDetails(
        uint256 _preSaleOpenTime,
        bytes32 _wlRoot,
        bytes32 _veRoot,
        bytes32 _freeRoot,
        uint256 _reserved
    ) external;

    function preSaleOpenTime() external view returns (uint256);

    function withdrawPTP() external;

    function setNewRoyaltyDetails(address _newAddress, uint256 _newFee) external;

    /*///////////////////////////////////////////////////////////////
                        PLATYPUS LEVEL MECHANICS
            Caretakers are other authorized contracts that
                according to their own logic can issue a platypus
                    to level up
    //////////////////////////////////////////////////////////////*/
    function caretakers(address) external view returns (uint256);

    function addCaretaker(address caretaker) external;

    function removeCaretaker(address caretaker) external;

    function growXp(uint256 tokenId, uint256 xp) external;

    function levelUp(
        uint256 tokenId,
        uint256 newAbility,
        uint256 newPower
    ) external;

    function levelDown(uint256 tokenId) external;

    function burn(uint256 tokenId) external;

    function changePlatypusName(uint256 tokenId, string calldata name) external;

    /*///////////////////////////////////////////////////////////////
                            PLATYPUS
    //////////////////////////////////////////////////////////////*/

    function getPlatypusXp(uint256 tokenId) external view returns (uint256 xp);

    function getPlatypusLevel(uint256 tokenId) external view returns (uint16 level);

    function getPrimaryAbility(uint256 tokenId) external view returns (uint8 ability, uint32 power);

    function getPlatypusDetails(uint256 tokenId)
        external
        view
        returns (
            uint32 speedo,
            uint32 pudgy,
            uint32 diligent,
            uint32 gifted,
            uint32 hibernate
        );

    function platypusesLength() external view returns (uint256);

    function setBaseURI(string memory _baseURI) external;

    function setNameFee(uint256 _nameFee) external;

    function getPlatypusName(uint256 tokenId) external view returns (string memory name);

    /*///////////////////////////////////////////////////////////////
                            MINTING
    //////////////////////////////////////////////////////////////*/
    function normalMint(uint256 numberOfMints) external;

    function veMint(
        uint256 numberOfMints,
        uint256 totalGiven,
        bytes32[] memory proof
    ) external;

    function wlMint(
        uint256 numberOfMints,
        uint256 totalGiven,
        bytes32[] memory proof
    ) external;

    function freeMint(
        uint256 numberOfMints,
        uint256 totalGiven,
        bytes32[] memory proof
    ) external;

    // comment to disable a slither false allert: PlatypusNFT does not implement functions
    // function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function _jsonString(uint256 tokenId) external view returns (string memory);

    function tokenURI(uint256 tokenId) external view returns (string memory);

    /*///////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    // event OwnerUpdated(address indexed newOwner);

    // ERC2981.sol
    // event ChangeRoyalty(address newAddress, uint256 newFee);

    /*///////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    // error FeeTooHigh();
    // error InvalidCaretaker();
    // error InvalidTokenID();
    // error MintLimit();
    // error PreSaleEnded();
    // error TicketError();
    // error TooSoon();
    // error Unauthorized();
}
