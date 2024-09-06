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

    uint256 private _currentTokenId; // Declare and initialize _currentTokenId

    struct Vehicle {
        uint256 autoIncrementId;
        string staticMetadataHash; // Hash of static metadata (e.g., VIN, make, model)
        string insuranceRecordHash;  // Hash of insurance records
        string carServiceRecordHash; // Hash of the latest car service record
        bool isStolen;             // Status of whether the car is reported stolen
        bool loanStatus;           // Status of the loan (true = clear, false = not clear)
        address ownerAddress;      // Address of the current owner (with zero-knowledge proof)
    }

    mapping(uint256 => Vehicle) public vehicles;
    mapping(address => bool) public authorizedManufacturers;
    mapping(address => bool) public authorizedInsuranceProviders;
    mapping(address => bool) public authorizedCarServiceProviders;
    mapping(address => bool) public certifiedUsers;
    mapping(uint256 => address) public vehicleOwners;
    mapping(uint256 => uint256) public vehiclePrices;

    event ManufacturerAuthorized(address manufacturer);
    event InsuranceProviderAuthorized(address provider);
    event CarServiceProviderAuthorized(address provider);
    event UserCertified(address user);
    event VehicleMinted(uint256 tokenId, address manufacturer, string staticMetadataHash);
    event VehicleListedForSale(uint256 tokenId, uint256 price);
    event VehiclePurchased(uint256 tokenId, address previousOwner, address newOwner, uint256 price);
    event VehicleReportedStolen(uint256 tokenId);
    event LoanCleared(uint256 tokenId);
    event StolenStatusConfirmed(uint256 tokenId);
    event LoanClearanceConfirmed(uint256 tokenId);
    event CarServiceRecordUpdated(uint256 tokenId, string newCarServiceRecordHash);
    event InsuranceRecordUpdated(uint256 tokenId, string insuranceRecordHash);

    constructor() ERC721("VehicleNFT", "VNFT") Ownable(msg.sender) {
        _currentTokenId = 0; // Initialize the token ID counter
    }

    modifier onlyAuthorizedManufacturer() {
        require(authorizedManufacturers[msg.sender], "Not an authorized manufacturer");
        _;
    }

    modifier onlyAuthorizedInsuranceProvider() {
        require(authorizedInsuranceProviders[msg.sender], "Not an authorized insurance provider");
        _;
    }

    modifier onlyAuthorizedCarServiceProvider() {
        require(authorizedCarServiceProviders[msg.sender], "Not an authorized car service provider");
        _;
    }

    modifier onlyCertifiedUser() {
        require(certifiedUsers[msg.sender], "Not a certified user");
        _;
    }

    modifier onlyCurrentOwner(uint256 tokenId) {
        require(ownerOf(tokenId) == msg.sender, "Not the current owner");
        _;
    }

    modifier isListedForSale(uint256 tokenId) {
        require(vehiclePrices[tokenId] > 0, "Vehicle not listed for sale");
        _;
    }

    modifier onlyRegulatoryAuthority() {
        require(msg.sender == owner(), "Only the regulatory authority can perform this action");
        _;
    }

    function authorizeManufacturer(address manufacturer) external onlyOwner {
        require(manufacturer != address(0), "Invalid address");
        authorizedManufacturers[manufacturer] = true;
        emit ManufacturerAuthorized(manufacturer);
    }

    function authorizeInsuranceProvider(address provider) external onlyOwner {
        require(provider != address(0), "Invalid address");
        authorizedInsuranceProviders[provider] = true;
        emit InsuranceProviderAuthorized(provider);
    }

    function authorizeCarServiceProvider(address provider) external onlyOwner {
        require(provider != address(0), "Invalid address");
        authorizedCarServiceProviders[provider] = true;
        emit CarServiceProviderAuthorized(provider);
    }
    
    function certifyUser(address user) external onlyOwner {
        certifiedUsers[user] = true;
        emit UserCertified(user);
    }

    function mintVehicle(
        string memory staticMetadataHash,
        string memory insuranceRecordHash,
        string memory initialCarServiceRecordHash
    ) external onlyAuthorizedManufacturer returns (uint256) {
        _currentTokenId++;
        uint256 newItemId = _currentTokenId;

        vehicles[newItemId] = Vehicle({
            autoIncrementId: newItemId,
            staticMetadataHash: staticMetadataHash,
            insuranceRecordHash: insuranceRecordHash,
            carServiceRecordHash: initialCarServiceRecordHash,
            isStolen: false,  // Default to not stolen
            loanStatus: false,  // Default to not clear
            ownerAddress: msg.sender
        });

        _mint(msg.sender, newItemId);
        _setTokenURI(newItemId, ""); // No metadata URI required for this update

        vehicleOwners[newItemId] = msg.sender;

        emit VehicleMinted(newItemId, msg.sender, staticMetadataHash);

        return newItemId;
    }

    function setInsuranceProvider(uint256 tokenId, address provider, string memory insuranceRecordHash) external onlyCurrentOwner(tokenId) {
        require(authorizedInsuranceProviders[provider], "Not an authorized insurance provider");

        // Update insurance record
        vehicles[tokenId].insuranceRecordHash = insuranceRecordHash;
        emit InsuranceRecordUpdated(tokenId, insuranceRecordHash);
    }

    function updateInsuranceRecord(uint256 tokenId, string memory newInsuranceRecordHash) external onlyAuthorizedInsuranceProvider {
    require(ownerOf(tokenId) != address(0), "VehicleNFT: Token ID does not exist");

    // Update the insurance record
    vehicles[tokenId].insuranceRecordHash = newInsuranceRecordHash;

    emit InsuranceRecordUpdated(tokenId, newInsuranceRecordHash);
    }

    function setCarServiceProvider(address provider) external onlyOwner {
    require(provider != address(0), "Invalid address");
    authorizedCarServiceProviders[provider] = true;
    emit CarServiceProviderAuthorized(provider);
    }

    function updateCarServiceRecord(uint256 tokenId, string memory newServiceRecordHash) external onlyAuthorizedCarServiceProvider {
        require(ownerOf(tokenId) != address(0), "VehicleNFT: Token ID does not exist");

        // Update the car service record
        vehicles[tokenId].carServiceRecordHash = newServiceRecordHash;

        emit CarServiceRecordUpdated(tokenId, newServiceRecordHash);
    }


    function listVehicleForSale(uint256 tokenId, uint256 price) external onlyCurrentOwner(tokenId) {
        Vehicle memory vehicle = vehicles[tokenId];

        require(!vehicle.isStolen, "Vehicle cannot be listed for sale because it is reported as stolen.");
        require(vehicle.loanStatus, "Vehicle cannot be listed for sale because the loan is not clear.");
        require(price > 0, "Price must be greater than zero");

        vehiclePrices[tokenId] = price;
        emit VehicleListedForSale(tokenId, price);
    }

    function purchaseVehicle(uint256 tokenId) external payable onlyCertifiedUser isListedForSale(tokenId) {
        address currentOwner = ownerOf(tokenId);
        uint256 price = vehiclePrices[tokenId];

        require(msg.value == price, "Incorrect payment amount");
        require(msg.sender != currentOwner, "Owner cannot purchase their own vehicle");

        _transfer(currentOwner, msg.sender, tokenId);
        vehicleOwners[tokenId] = msg.sender;
        vehiclePrices[tokenId] = 0;

        payable(currentOwner).transfer(msg.value);

        emit VehiclePurchased(tokenId, currentOwner, msg.sender, msg.value);
    }

    function reportStolen(uint256 tokenId) external onlyCurrentOwner(tokenId) {
        vehicles[tokenId].isStolen = true;
        emit VehicleReportedStolen(tokenId);
    }

    function confirmStolenStatus(uint256 tokenId) external onlyRegulatoryAuthority {
        require(vehicles[tokenId].isStolen == true, "Vehicle has not been reported stolen.");

        // Additional logic can be added here, such as changing ownership or flagging the vehicle
        
        emit StolenStatusConfirmed(tokenId);
    }

    function clearLoan(uint256 tokenId) external onlyCurrentOwner(tokenId) {
        vehicles[tokenId].loanStatus = true;  // Mark loan as clear (true = clear)
        emit LoanCleared(tokenId);
    }

    function confirmLoanClearance(uint256 tokenId) external onlyRegulatoryAuthority {
        require(vehicles[tokenId].loanStatus == true, "Loan has not been reported clear.");

        // Additional logic can be added here
        
        emit LoanClearanceConfirmed(tokenId);
    }

    function getVehicle(uint256 tokenId) external view returns (Vehicle memory) {
        require(ownerOf(tokenId) != address(0), "VehicleNFT: Token ID does not exist");
        return vehicles[tokenId];
    }
}
