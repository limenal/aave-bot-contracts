// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.12;
import {ILendingPool} from "@aave/protocol-v2/contracts/interfaces/ILendingPool.sol";
import "./ERC20.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Router.sol";
contract Redeposit is Ownable{
    
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    
    address constant public WMATIC = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    address constant public pool = address(0x9198F13B08E299d85E096929fA9781A1E3d5);
    address constant public quickswapRouter  = address(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);
    
    uint256 public totalDeposits;
    uint256 public sumOfRewards;
    uint256 public sumOfPreviousRewards;
    
    address public currentToken;
    address public currentAaveToken;
    
    mapping(address => uint256) public currentDeposit;
    mapping(address => bool) public isDeposited;
    mapping(address => uint256) public sumOfRewardsForUser;
    mapping(address => address) public aTokens;
    
    address[] public path;
    
    address[] public users;
    
    constructor() public
    {
        sumOfPreviousRewards = 0;
        totalDeposits = 0;
        sumOfRewards = 0;
    }
    
    function setMaxToken(address token, address aToken) external onlyOwner{
        if(currentToken != token)
        {
            //swap(currentToken => token)
            //Recalculating all deposits
            currentToken = token;
            currentAaveToken = aToken;
        }
        else if(totalDeposits == 0){
            currentToken = token;
            currentAaveToken = aToken;
        }
    }
    
    function getTokenAddress(uint256 _index) public view returns (address){
        address[] memory reserves = ILendingPool(pool).getReservesList();
        return reserves[_index];
    }
    
    function swapTokens(address newToken) internal{
        
        ILendingPool(pool).withdraw(currentToken, type(uint).max, address(this));
        
        uint256 totalDepositsBeforeSwap = IERC20(currentToken).balanceOf(address(this));
        
        path = [currentToken, newToken];
        
        IUniswapV2Router01(quickswapRouter).swapExactTokensForTokens(totalDepositsBeforeSwap, 0, path, address(this), now.add(600));
        
        uint256 totalDepositsAfterSwap = IERC20(newToken).balanceOf(address(this));
        
        totalDeposits = totalDeposits.mul(totalDepositsAfterSwap).div(totalDepositsBeforeSwap);
        for(uint i = 0; i < users.length; ++i)
        {
            currentDeposit[users[i]] = currentDeposit[users[i]].mul(totalDepositsAfterSwap).div(totalDepositsBeforeSwap);
        }
        sumOfPreviousRewards = sumOfPreviousRewards.mul(totalDepositsAfterSwap).div(totalDepositsBeforeSwap);
        
    }
    
    function deposit(address token, uint256 amount) public {
        require(isDeposited[msg.sender] == false);
        //if(token != currentToken)
        //swap()
        if(totalDeposits > 0)
        {
            distributeUSD();
            sumOfRewardsForUser[msg.sender] = sumOfRewards;
        }
        else{
            sumOfRewardsForUser[msg.sender] = 0;
        }
        isDeposited[msg.sender] = true;
        currentDeposit[msg.sender] = amount;
        totalDeposits = totalDeposits.add(amount);
        ILendingPool(pool).deposit(token, amount, address(this), 0);
        users.push(address(msg.sender));
    }
    
    function withdraw(address asset, address to) public {
        distributeUSD();
        require(currentDeposit[msg.sender] > 0 && sumOfRewards > 0);
        isDeposited[msg.sender] = false;
        uint256 deposited = currentDeposit[msg.sender];
        uint256 reward = deposited.mul(sumOfRewards.sub(sumOfRewardsForUser[msg.sender])).div(uint256(1 ether));
        uint withdrawal = deposited.add(reward);
        ILendingPool(pool).withdraw(asset, withdrawal, msg.sender);
        totalDeposits = totalDeposits.sub(deposited);
    }
    
    function distributeUSD() internal {
        require(totalDeposits > 0);
        
        uint256 reward = IERC20(currentAaveToken).balanceOf(address(this)).sub(totalDeposits).sub(sumOfPreviousRewards);
        sumOfPreviousRewards = sumOfPreviousRewards.add(reward);
        sumOfRewards = sumOfRewards.add(uint256(1 ether).mul(reward).div(totalDeposits));
    }
    //to do
    function distributeMatic() external onlyOwner{
        
        
    }
    
}