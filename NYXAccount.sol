/*
* Copyright © 2017 NYX. All rights reserved.
*/
pragma solidity ^0.4.15;

contract NYX {
    /// Count request access escrow
    uint public voteCounter = 0;
    /// Unlock access threshold - how much escrows should vote in order to trigger transfer of funds
    uint public unlockTreshold = 0;
    /// Container to collect escrow's votes for restoring access
    mapping(address => bool) public identificationState;
    /// Address to which restore funds from this address
    address public restoreAddress;
    /// Cost of the access request.
    uint public restoreAccessPrice = 0.001 ether;
    /// These are addresses that will participate in recovering access to this account when the access is lost
    address[10] public escrows;
    /// This will allow you to transfer money to Emergency account
    /// if you loose access to your Owner and Resque account's private key/passwords.
    /// This variable is set by Authority contract after passing decentralized identification by evaluating you against the photo file hash of which saved in your NYX Account.
    /// Your emergency account hash should contain hash of the pair <your secret phrase> + <your Emergency account's address>.
    /// This way your hash is said to be "signed" with your secret phrase.
	bytes32 emergencyHash;
	/// Authority contract address, which is allowed to set your Emergency account (see variable above)
    address authority;
    /// Your Owner account by which this instance of NYX Account is created and run
    address public owner;
    /// Hash of address of your Resque account
    bytes32 resqueHash;
    /// Hash of your secret key phrase
    bytes32 keywordHash;
    /// This will be hashes of photo files of your people to which you wish grant access
    /// to this NYX Account. Up to 10 persons allowed. You must provide one
    /// of photo files, hash of which is saved to this variable upon NYX Account creation.
    /// The person to be identified must be a person in the photo provided.
    bytes32[10] photoBzzLinks;
    /// The datetime value when transfer to Resque account was first time requested.
    /// When you request withdrawal to your Resque account first time, only this variable set. No actual transfer happens.
    /// Transfer will be executed after 1 day of "quarantine". Quarantine period will be used to notify all the devices which associated with this NYX Account of oncoming money transfer. After 1 day of quarantine second request will execute actual transfer.
    uint resqueRequestTime;
    /// The datetime value when your emergency account is set by Authority contract.
    /// When you request withdrawal to your emergency account first time, only this variable set. No actual transfer happens.    
    /// Transfer will be executed after 1 day of "quarantine". Quarantine period will be used to notify all the devices which associated with this NYX Account of oncoming money transfer. After 1 day of quarantine second request will execute actual transfer.
    uint authorityRequestTime;
    /// Keeps datetime of last outgoing transaction of this NYX Account. Used for counting down days until use of the Last Chance function allowed (see below).
	uint lastExpenseTime;
	/// Enables/disables Last Chance function. By default disabled.
	bool public lastChanceEnabled = false;
	/// Whether knowing Resque account's address is required to use Last Chance function? By default - yes, it's required to know address of Resque account.
	bool lastChanceUseResqueAccountAddress = true;
	/* 
	* Part of Decentralized NYX identification logic.
	* This event places NYX identification request in the blockchain.
	* Others will watch for it and take part in identification process.
	* swarmLinkVideo: video file provided by owner of this NYX Account for identification against swarmLinkPhoto
	*/
    event NYXDecentralizedIdentificationRequest(address to, string swarmLinkVideo);
	
    /// Enumerates states of NYX Account
    enum Stages {
        Normal, // Everything is ok, this account is running by your managing (owning) account (address)
        ResqueRequested, // You have lost access to your managing account and  requested to transfer all the balance to your Resque account
        AuthorityRequested // You have lost access to both your Managing and Resque accounts. Authority contract set Emergency account provided by you, to transfer balance to the Emergency account. For using this state your secret phrase must be available.
    }
    /// Defaults to Normal stage
    Stages stage = Stages.Normal;

    /* Constructor taking
    * resqueAccountHash: keccak256(address resqueAccount);
    * authorityAccount: address of authorityAccount that will set data for withdrawing to Emergency account
    * kwHash: keccak256("your keyword phrase");
    * photoBzzs: array of swarm links to media materials of the account's owner - for future decentralized identification. 
    */
    function NYX(bytes32 resqueAccountHash, address authorityAccount, bytes32 kwHash, bytes32[10] photoBzzs) public {
        owner = msg.sender;
        resqueHash = resqueAccountHash;
        authority = authorityAccount;
        keywordHash = kwHash;
        // save photo hashes as state forever
        uint8 x = 0;
        while (x < photoBzzs.length) {
            photoBzzLinks[x] = photoBzzs[x];
            x++;
        }
    }
    
    /// Escrow voting for access recovery. Only addresses registered in "escrows" allowed to vote.
    function recoveryVote() onlyEscrow public {
        /// Add vote to the identification state
        identificationState[msg.sender] = true;
        /// Send money to escrow for his vote 
        msg.sender.transfer(restoreAccessPrice);
        voteCounter++;
        
        /// If number of votes achieved unlockTreshold - send this account's balance to the restoreAddress
        if (voteCounter >= unlockTreshold)
            restoreAddress.transfer(this.balance);
    }
    
    /// Set price for an escrow's vote. This amount will be transfered to each of the voting escrows.
    function setRestoreAccessPrice(uint newPrice) onlyByOwner public {
        restoreAccessPrice = newPrice;
    }
    
    /// Set required number of escrow's votes. When achieved, balance will be transfered to the restoreAddress.
    function setUnlockTreshold(uint treshold) onlyByOwner public {
        unlockTreshold = treshold;
    }
    
    /// Publish restore request to the blockchain. Pass swarm link to the video which will be used to identify requester as owner of this (lost) account.
    /// Pass along with the function call some ether, the amount should be greater then price for a single escrows' vote.
    function restoreAccess(string bzzVideo) payable public {
        /// Check that passed money is greater than price for a single escrow's vote
        require(msg.value >= restoreAccessPrice);
        
        /// Set calling address as restore address to which funds will be transfered upon successful restore.
        restoreAddress = msg.sender;
        
        /// Publish event that contains address for restoring funds and video for decentralized identification
        /// Escrows are watching for this event on their client apps and use the data supplied with this event to participate in the identification
        NYXDecentralizedIdentificationRequest(msg.sender, bzzVideo);
    }
    
    /// Modifiers
    
    /// Restrict restore voting only to the addresses set by the owner in "ecrows" variable
    modifier onlyEscrow() {
         uint8 x = 0;
         bool found = false;
        while (x < escrows.length) {
            if (escrows[x] == msg.sender)
                found = true;
        }
        require(found);

        _;
    }
    
    modifier onlyByResque()
    {
        require(keccak256(msg.sender) == resqueHash);
        _;
    }
    modifier onlyByAuthority()
    {
        require(msg.sender == authority);
        _;
    }
    modifier onlyByOwner() {
        require(msg.sender == owner);
        _;
    }
    modifier onlyByEmergency(string keywordPhrase) {
        require(keccak256(keywordPhrase, msg.sender) == emergencyHash);
        _;
    }
    
    // Replace escrows
    function replaceEscrows(address[10] newEscrows) onlyByOwner() public {
        escrows = newEscrows;
    }

    // Switch on/off Last Chance function
	function toggleLastChance(bool useResqueAccountAddress) onlyByOwner() public {
	    // Only allowed in normal stage to prevent changing this by stolen Owner's account
	    require(stage == Stages.Normal);
	    // Toggle Last Chance function flag
		lastChanceEnabled = !lastChanceEnabled;
		// If set to true knowing of Resque address (not key or password) will be required to use Last Chance function
		lastChanceUseResqueAccountAddress = useResqueAccountAddress;
	}
	
	// Standard transfer Ether using Owner account
    function transferByOwner(address recipient, uint amount) onlyByOwner() payable public {
        // Only in Normal stage possible
        require(stage == Stages.Normal);
        // Amount must not exeed this.balance
        require(amount <= this.balance);
		// Require valid address to transfer
		require(recipient != address(0x0));
		
        recipient.transfer(amount);
        // This is used by Last Chance function
		lastExpenseTime = now;
    }

    /// Withdraw to Resque Account in case of loosing Owner account access
    function withdrawByResque() onlyByResque() public {
        // If not already requested (see below)
        if (stage != Stages.ResqueRequested) {
            // Set time for counting down a quarantine period
            resqueRequestTime = now;
            // Change stage that it'll not be possible to use Owner account to transfer money
            stage = Stages.ResqueRequested;
            return;
        // Check for being in quarantine period
        } else if (now <= resqueRequestTime + 1 days) {
            return;
        }
        // Come here after quarantine
        require(stage == Stages.ResqueRequested);
        msg.sender.transfer(this.balance);
    }

    /* 
    * Setting Emergency Account in case of loosing access to Owner and Resque accounts
    * emergencyAccountHash: keccak256("your keyword phrase", address ResqueAccount)
    * photoHash: keccak256("one_of_your_photofile.pdf_data_passed_to_constructor_of_this_NYX_Account_upon_creation")
    */
    function setEmergencyAccount(bytes32 emergencyAccountHash, bytes32 photoHash) onlyByAuthority() public {
        require(photoHash != 0x0 && emergencyAccountHash != 0x0);
        /// First check that photoHash is one of those that exist in this NYX Account
        uint8 x = 0;
        bool authorized = false;
        while (x < photoBzzLinks.length) {
            if (photoBzzLinks[x] == keccak256(photoHash)) {
            // Photo found, continue
                authorized = true;
                break;
            }
            x++;
        }
        require(authorized);
        /// Set count down time for quarantine period
        authorityRequestTime = now;
        /// Change stage in order to protect from withdrawing by Owner's or Resque's accounts 
        stage = Stages.AuthorityRequested;
        /// Set supplied hash that will be used to withdraw to Emergency account after quarantine
		emergencyHash = emergencyAccountHash;
    }
   
    /// Withdraw to Emergency Account after loosing access to both Owner and Resque accounts
	function withdrawByEmergency(string keyword) onlyByEmergency(keyword) public {
		require(now > authorityRequestTime + 1 days);
		require(keccak256(keyword) == keywordHash);
		require(stage == Stages.AuthorityRequested);
		
		msg.sender.transfer(this.balance);
	}

    /*
    * Allows optionally unauthorized withdrawal to any address after loosing 
    * all authorization assets such as keyword phrase, photo files, private keys/passwords
    */
	function lastChance(address recipient, address resqueAccount) public {
	    /// Last Chance works only if was previosly enabled AND after 2 months since last outgoing transaction
		if (!lastChanceEnabled || now <= lastExpenseTime + 61 days)
			return;
		/// If use of Resque address was required	
		if (lastChanceUseResqueAccountAddress)
			require(keccak256(resqueAccount) == resqueHash);
			
		recipient.transfer(this.balance);			
	}	
	
    /// Fallback for receiving plain transactions
    function() payable public {
        /// Refuse accepting funds in abnormal state
        require(stage == Stages.Normal);
    }
}