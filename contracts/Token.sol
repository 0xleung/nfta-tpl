// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./tokens/ERC721A.sol";

contract Token is ERC721A, Ownable, ReentrancyGuard {
    using ECDSA for bytes32;

    enum Status {
        Pending,
        PreSale,
        PublicSale,
        Finished
    }

    Status public status;
    string public baseURI;
    address private _signer;
    uint256 public tokensReserved;
    uint256 public immutable maxMint;
    uint256 public immutable maxSupply;
    uint256 public immutable reserveAmount;
    uint256 public constant PRICE = 0.0502 * 10**18; // 0.0502 ETH
    bool public balanceWithdrawn;

    mapping(address => bool) public publicMinted;

    event Minted(address minter, uint256 amount);
    event StatusChanged(Status status);
    event SignerChanged(address signer);
    event ReservedToken(address minter, address recipient, uint256 amount);
    event BaseURIChanged(string newBaseURI);

    constructor(
        string memory initBaseURI,
        address signer,
        uint256 _maxBatchSize,
        uint256 _collectionSize,
        uint256 _reserveAmount
    ) ERC721A("Token", "Token", _maxBatchSize, _collectionSize) {
        baseURI = initBaseURI;
        _signer = signer;
        maxMint = _maxBatchSize;
        maxSupply = _collectionSize;
        reserveAmount = _reserveAmount;
    }

    function _hash(string calldata salt, address _address)
        internal
        view
        returns (bytes32)
    {
        return keccak256(abi.encode(salt, address(this), _address));
    }

    function _verify(bytes32 hash, bytes memory token)
        internal
        view
        returns (bool)
    {
        return (_recover(hash, token) == _signer);
    }

    function _recover(bytes32 hash, bytes memory token)
        internal
        pure
        returns (address)
    {
        return hash.toEthSignedMessageHash().recover(token);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function reserve(address recipient, uint256 amount) external onlyOwner {
        require(recipient != address(0), "Token: zero address");
        require(amount > 0, "Token: invalid amount");
        require(
            totalSupply() + amount <= collectionSize,
            "Token: max supply exceeded"
        );
        require(
            tokensReserved + amount <= reserveAmount,
            "Token: max reserve amount exceeded"
        );
        require(
            amount % maxBatchSize == 0,
            "Token: can only mint a multiple of the maxBatchSize"
        );

        uint256 numChunks = amount / maxBatchSize;
        for (uint256 i = 0; i < numChunks; i++) {
            _safeMint(recipient, maxBatchSize);
        }
        tokensReserved += amount;
        emit ReservedToken(msg.sender, recipient, amount);
    }

    function presaleMint(
        uint256 amount,
        string calldata salt,
        bytes calldata token
    ) external payable {
        require(status == Status.PreSale, "Token: Presale is not active.");
        require(
            tx.origin == msg.sender,
            "Token: contract is not allowed to mint."
        );
        require(_verify(_hash(salt, msg.sender), token), "Token: Invalid token.");
        require(
            numberMinted(msg.sender) + amount <= maxMint,
            "Token: Max mint amount per wallet exceeded."
        );
        require(
            totalSupply() + amount + reserveAmount - tokensReserved <=
                collectionSize,
            "Token: Max supply exceeded."
        );

        _safeMint(msg.sender, amount);
        refundIfOver(PRICE * amount);

        emit Minted(msg.sender, amount);
    }

    function mint() external payable {
        require(status == Status.PublicSale, "Token: Public sale is not active.");
        require(
            tx.origin == msg.sender,
            "Token: contract is not allowed to mint."
        );
        require(
            !publicMinted[msg.sender],
            "Token: The wallet has already minted during public sale."
        );
        require(
            totalSupply() + 1 + reserveAmount - tokensReserved <=
                collectionSize,
            "Token: Max supply exceeded."
        );

        _safeMint(msg.sender, 1);
        publicMinted[msg.sender] = true;
        refundIfOver(PRICE);

        emit Minted(msg.sender, 1);
    }

    function refundIfOver(uint256 price) private {
        require(msg.value >= price, "Token: Need to send more ETH.");
        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }
    }

    function withdraw() external nonReentrant onlyOwner {
        require(
            status == Status.Finished,
            "Token: invalid status for withdrawn."
        );
        require(!balanceWithdrawn, "Token: balance has already been withdrawn.");

        uint256 balance = address(this).balance;

        // uint256 v1 = 3.5 * 10**18;
        // uint256 v2 = 0.5 * 10**18;
        // uint256 v3 = balance - v1 - v2;
        // uint256 v1 = balance;

        balanceWithdrawn = true;

        (bool success1, ) = payable(0x36d8d59611e74EA778EfE4B3a3203Cb88070B355)
            .call{value: balance}("");
        // (bool success2, ) = payable(0xb811EC5250796966f1400C8e30E5e8A2bC44a068)
        //     .call{value: v2}("");
        // (bool success3, ) = payable(0xe9EAA95B03f40F13C5609b54e40C155e6f77f648)
        //     .call{value: v3}("");

        require(success1, "Transfer 1 failed.");
        // require(success2, "Transfer 2 failed.");
        // require(success3, "Transfer 3 failed.");
    }

    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        baseURI = newBaseURI;
        emit BaseURIChanged(newBaseURI);
    }

    function setStatus(Status _status) external onlyOwner {
        status = _status;
        emit StatusChanged(_status);
    }

    function setSigner(address signer) external onlyOwner {
        _signer = signer;
        emit SignerChanged(signer);
    }

    function setOwnersExplicit(uint256 quantity)
        external
        onlyOwner
        nonReentrant
    {
        _setOwnersExplicit(quantity);
    }

    function numberMinted(address owner) public view returns (uint256) {
        return _numberMinted(owner);
    }

    function getOwnershipData(uint256 tokenId)
        external
        view
        returns (TokenOwnership memory)
    {
        return ownershipOf(tokenId);
    }
}