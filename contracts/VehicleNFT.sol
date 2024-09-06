// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title VehicleNFT Contract
/// @dev ERC721 contract for managing vehicles with features like minting, listing, and purchasing
contract VehicleNFT is ERC721URIStorage, Ownable {
    using ECDSA for bytes32;
    using SignatureChecker for address;

    struct Vehicle {
        bytes32 merkleRoot;
        bool isStolen;
    }

    uint256 private _currentTokenId;

    mapping(uint256 => Vehicle) public vehicles;
    mapping(address => bool) public authorizedManufacturers;
    mapping(address => bool) public certifiedUsers;
    mapping(uint256 => address) public vehicleOwners;
    mapping(uint256 => uint256) public vehiclePrices;

    event ManufacturerAuthorized(address manufacturer);
    event UserCertified(address user);
    event VehicleMinted(
        uint256 tokenId,
        address manufacturer,
        bytes32 merkleRoot
    );
    event VehicleListedForSale(uint256 tokenId, uint256 price);
    event VehiclePurchased(uint256 tokenId, address previousOwner, address newOwner, uint256 price);
    event VehicleReportedStolen(uint256 tokenId);
    event StolenStatusConfirmed(uint256 tokenId);
    event PriceUpdated(uint256 tokenId, uint256 newPrice);

    constructor() ERC721("VehicleNFT", "VNFT") Ownable(msg.sender) {}

    /// @dev Modifier to allow only authorized manufacturers to call certain functions
    modifier onlyAuthorizedManufacturer() {
        require(
            authorizedManufacturers[msg.sender],
            "Not an authorized manufacturer"
        );
        _;
    }

    /// @dev Modifier to allow only certified users to call certain functions
    modifier onlyCertifiedUser() {
        require(certifiedUsers[msg.sender], "Not a certified user");
        _;
    }

    /// @dev Modifier to ensure only the current owner of a vehicle can call certain functions
    modifier onlyCurrentOwner(uint256 tokenId) {
        require(ownerOf(tokenId) == msg.sender, "Not the current owner");
        _;
    }

    /// @dev Modifier to ensure the vehicle is listed for sale
    modifier isListedForSale(uint256 tokenId) {
        require(vehiclePrices[tokenId] > 0, "Vehicle not listed for sale");
        _;
    }

    /// @notice Authorizes a manufacturer to mint vehicles
    /// @param manufacturer The address of the manufacturer to authorize
    function authorizeManufacturer(address manufacturer) external onlyOwner {
        require(manufacturer != address(0), "Invalid address"); // Check for invalid address
        authorizedManufacturers[manufacturer] = true;
        emit ManufacturerAuthorized(manufacturer);
    }

    /// @notice Certifies a user to purchase vehicles
    /// @param user The address of the user to certify
    function certifyUser(address user) external onlyOwner {
        certifiedUsers[user] = true;
        emit UserCertified(user);
    }

    /// @notice Mints a new vehicle and lists it for sale
    /// @param merkleRoot The Merkle root of the vehicle data
    /// @param price The sale price of the vehicle
//    /// @param signature The signature to verify the manufacturer
    /// @return newItemId The ID of the newly minted vehicle
    function mintVehicle(
        bytes32 merkleRoot,
        uint256 price
//        bytes calldata signature
    ) external onlyAuthorizedManufacturer returns (uint256) {
        _currentTokenId++;
        uint256 newItemId = _currentTokenId;

        // // Signature verification
        // bytes32 messageHash = keccak256(
        //     abi.encodePacked(msg.sender, merkleRoot, price, newItemId)
        // );
        // bytes32 ethSignedMessageHash = keccak256(
        //     abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        // );

        // require(
        //     SignatureChecker.isValidSignatureNow(
        //         msg.sender,
        //         ethSignedMessageHash,
        //         signature
        //     ),
        //     "Invalid signature"
        // );

        _mint(msg.sender, newItemId);
        _setTokenURI(newItemId, ""); // No metadata URI required for this update

        vehicles[newItemId] = Vehicle(merkleRoot, false); // Store Merkle root
        vehicleOwners[newItemId] = msg.sender;
        vehiclePrices[newItemId] = price;

        // Automatically list the vehicle for sale
        emit VehicleMinted(newItemId, msg.sender, merkleRoot);
        emit VehicleListedForSale(newItemId, price);

        return newItemId;
    }

    /// @notice Lists a vehicle for sale
    /// @param tokenId The ID of the vehicle to list
    /// @param price The sale price of the vehicle
    function listVehicleForSale(
        uint256 tokenId,
        uint256 price
    ) external onlyCurrentOwner(tokenId) {
        require(!vehicles[tokenId].isStolen, "Vehicle is reported stolen");
        require(price > 0, "Price must be greater than zero");
        vehiclePrices[tokenId] = price;
        emit VehicleListedForSale(tokenId, price);
    }

    /// @notice Purchases a vehicle if it is listed for sale and the caller is a certified user
    /// @param tokenId The ID of the vehicle to purchase
    function purchaseVehicle(
        uint256 tokenId
    ) external payable onlyCertifiedUser isListedForSale(tokenId) {
        require(!vehicles[tokenId].isStolen, "Vehicle is reported stolen");
        address currentOwner = ownerOf(tokenId);
        uint256 price = vehiclePrices[tokenId];

        require(msg.value == price, "Incorrect payment amount");
        require(
            msg.sender != currentOwner,
            "Owner cannot purchase their own vehicle"
        );

        _transfer(currentOwner, msg.sender, tokenId);
        vehicleOwners[tokenId] = msg.sender;
        vehiclePrices[tokenId] = 0;

        payable(currentOwner).transfer(msg.value);

        emit VehiclePurchased(tokenId, currentOwner, msg.sender, msg.value);
    }

    /// @notice Sets a new price for a vehicle
    /// @param tokenId The ID of the vehicle to update
    /// @param newPrice The new sale price of the vehicle
    function setPrice(
        uint256 tokenId,
        uint256 newPrice
    ) external onlyCurrentOwner(tokenId) {
        vehiclePrices[tokenId] = newPrice;
        emit PriceUpdated(tokenId, newPrice);
    }

    /// @notice Reports a vehicle as stolen
    /// @param tokenId The ID of the vehicle to report
    function reportStolen(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Not the owner");
        vehicles[tokenId].isStolen = true;
        emit VehicleReportedStolen(tokenId);
    }

    /// @notice Confirms that a vehicle has been reported stolen
    /// @param tokenId The ID of the vehicle to confirm
    function confirmStolen(uint256 tokenId) external onlyOwner {
        require(vehicles[tokenId].isStolen, "Vehicle not reported stolen");
        emit StolenStatusConfirmed(tokenId);
    }

   
 /// @notice Retrieves the Merkle root for a given vehicle token ID.
 ///  @param tokenId The ID of the vehicle token.
 ///  @return The Merkle root associated with the given token ID.
 /// @dev Reverts if the token ID does not exist.

    function getVehicleMerkleRoot(
    uint256 tokenId
    ) external view returns (bytes32) {
    require(_ownerOf(tokenId) != address(0), "VehicleNFT: Token ID does not exist");
    return vehicles[tokenId].merkleRoot;
    }

    /// @notice Checks if a vehicle has been reported stolen
    /// @param tokenId The ID of the vehicle
    /// @return True if the vehicle is reported stolen, false otherwise
    function isVehicleStolen(uint256 tokenId) external view returns (bool) {
        return vehicles[tokenId].isStolen;
    }

    /// @notice Verifies a Merkle proof for a vehicle
    /// @param tokenId The ID of the vehicle
    /// @param proof The Merkle proof to verify
    /// @param leaf The leaf node to verify
    /// @return True if the proof is valid, false otherwise
    function verifyMerkleProof(
        uint256 tokenId,
        bytes32[] calldata proof,
        bytes32 leaf
    ) external view returns (bool) {
        bytes32 root = vehicles[tokenId].merkleRoot;
        return _verifyMerkleProof(root, proof, leaf);
    }

    /// @notice Verifies a Merkle proof against a root
    /// @param root The Merkle root
    /// @param proof The Merkle proof to verify
    /// @param leaf The leaf node to verify
    /// @return True if the proof is valid, false otherwise
    function _verifyMerkleProof(
        bytes32 root,
        bytes32[] calldata proof,
        bytes32 leaf
    ) public pure returns (bool) {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            if (computedHash < proofElement) {
                computedHash = keccak256(
                    abi.encodePacked(computedHash, proofElement)
                );
            } else {
                computedHash = keccak256(
                    abi.encodePacked(proofElement, computedHash)
                );
            }
        }
        return computedHash == root;
    }
}
