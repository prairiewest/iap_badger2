local Library = require "CoronaLibrary"
local public = Library:new{ name='iap_badger2', publisherId='net.prairiewest' }

--Store library
local store={}
public.store=store

local version=19

--[[

IAP badger - unified in-app purchases.

Currently supports: iOS App Store / Google Play / Amazon / simulator

Changelog
---------

Version 19
* Removed all reverences to old Google store plugin (its API level is too low, Google will no longer accept apps using it)
* Updated iOS store plugin
* Updated Amazon store plugin
* Updated Google store plugin
* Added code to handle subscription purchases
* Added Google subscription verification via server

Version 18
* purchases on Google Store that fail because the user already owns the specified item are now converted into standard purchase events (to replicate behaviour on iOS).  This can be turned on/off with the googleConvertOwnedPurchaseEvents flag during initialisation.
* On Android, warnings given if no build store has been selected in the Corona build dialog

Version 17
* corrected declaration of emptyInventoryOfNonConsumableItems

Version 16
* fixed checkProductExists bug (thanks to bogomazon)

Version 15
* bug fixes
* better handling of store on iOS if user not logged in

Version 14
* Fixed bug introduced in version 12 on Android devices that mishandled failed/cancelled events
* Better handling (and improved consistency between devices) of transaction receipts

Version 13
* Fixed bug introduced in version 12 that would make cancelled or failed restores in debug mode fail

Version 12
* added switch to ignore unknown product codes on purchase/restore - handleInvalidProductIDs
* downgraded invalid product IDs from an error that halts execution to a printed error to terminal
* added switch in catalogue to allow restore of individual consumable products (set allowRestore to true) - note that this item will now be included when running a restore cycle in debug mode
* removed some of instructional comments from the source code (out of date and better documentation available on http://happymongoose.co.uk anyway
* improved some debug output detail on verboseDebugOutput
* fixed incorrect error messages on consumption events on Google Play

Version 11
* fixed loadProducts not working correctly on simulator (when not passed a callback function)

Version 10
* fixed crash bug introduced by verboseDebugOutput when testing cancelled/failed restores on the simulator

Version 9
* added verboseDebugOutput for some functions
* added automatic build number check to see whether IAP Badger needs to run in synchronous mode for new Google IAP v3 interface

Version 8.02
* redacted

Version 8:
* updated for Google IAP update (store.init now asynchronous)
* added getVersion(), consumeAllProducts() and printLoadProductsCatalogue() functions
* improved handling of loadProducts in debug mode or on the simulator, so it better simulates the delay experienced on a real device

Version 7:
* decoupled inventory handling from IAP handling

Version 6:
* loadProducts - fixed user listener not being called correctly (again)
* loadProducts - for convenience, the user listener is now called with (raw product data, loadProductsCatalogue) on device;
*                   ({}, loadProductsCatalogue) on simulator.

Version 5:
* fix to getLoadProductsFinished when running in debug mode

Version 4:
* removed reference to stores.availableStores.apple

Version 3:
* fixed store loading (defaulting to Apple) on non-iOS devices

Version 2:
* support added for Amazon IAP v2
* removed generateAmazonJSON() function as it is no longer required (JSON testing file can now be downloaded from Amazon's website)
* fixed null productID passed on fake cancelled/failed restore events
* changes to loadInventory and saveInventory to add ability to load and save directly from a string instead of a device file (to allow for cloud saving etc.)
* added getLoadProductsFinished() - returns true if loadProducts has received information back from the store, false if loadProducts still waiting, nil if loadProducts never called


General features:
* a unified approach to calling store and IAP whether you're on the App Store, Google Play, or wherever
* simplified calling and testing of IAP functions, just provide a list of products and some simple callbacks for when items are purchased / restored or
  refunded
* simplified product maintenance (adding/removing products from the inventory)
* handles loading / saving of items that have been purchased
* put IAP badger in debug mode to test IAP functions in your app (purchase / restore) without having to contact real stores
* products can have different names across the range of stores (so an upgrade called 'COIN_UPGRADE' in iTunes  Connect could be called
  'coins_purchased' in Google Play)
* different product types available (consumable or non-consumable)

Inventory / security features:
* customise the filename used to save the contents of the inventory
* inventory file contents can be hashed to prevent unauthorised changes (specify a 'salt' in the init() function).
* a customisable 'salt' can be applied to the contents so no two Corona apps produce the same hash for the same inventory contents.  (Empty inventories
  are saved without a hash, to make it more difficult to reverse engineer the salt.)
* product names can be refactored (renamed) in the save file to disguise their true function
* quantities / values can also be disguised / obfuscated
* 'random items' can be added to the inventory, whose values change randomly with each save, to help disguise the function of other quantities
  being saved at the same time.
* IAP badger can generate a Amazon test JSON file for you, to help with testing on Amazon hardware




This code is released under an MIT license, so you're free to do what you want with it -
though it would be great that if you forked or improved it, those improvements were
given back to the community :)

    The MIT License (MIT)

    Copyright (c) 2025 Prairiewest github.com/prairiewest

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.


--]]


--Product catalogue
local catalogue=nil

--The app package name (ie: com.example.myapp)
local packageName=nil

--User inventory
local inventory=nil
public.inventory=inventory

local refactorTable=nil
public.refactorTable=refactorTable

--Filename for inventory
local filename=nil
public.filename=filename

--URL for purchase receipt verification
local receiptVerifyURL=nil

--Salt used to hash contents (if required by user)
local salt=nil
--Requires crypto library
local crypto = require("crypto")

--Is the store available?
local storeAvailable=false
local function isStoreAvailable() return storeAvailable end
public.isStoreAvailable=isStoreAvailable

--Forward references
local storeTransactionCallback
local verifyReceipt
local verifyReceiptListener
local fakeRestore
local fakeRestoreListener
local fakeRestoreProducts
local fakePurchase
local loadProducts
local loadProductsCallback
local restore
local purchase
local retryCount = 0
local onSimulator = false

--Switches (and default values)
local handleInvalidProductIDs=false

--Restore purchases timer
local restorePurchasesTimer=nil
--Transaction failed / cancelled listeners
local transactionFailedListener=nil
local transactionCancelledListener=nil

--Info about last transaction
local previouslyRestoredTransactions=nil
local asyncState=nil

--Target store
local targetStore=nil
--Debug mode
local debugMode=false
-- Has init been completed
local initDone=false
--Store to debug as
local debugStore="apple"
--Verbose debug output to console?
local verboseDebugOutput=nil

--Standard response to bad hash
local badHashResponse="errorMessage"

--A convenience function - returns a user friendly name for the current app store
local storeNames = { apple="the App Store", google="Google Play", amazon="Amazon", none="a simulated app store"}
local storeName = nil

--Function to call after storeTransactionCallback (optional parameter to purchase function)
local postStoreTransactionCallbackListener=nil
local postRestoreCallbackListener=nil
local fakeRestoreTimeoutFunction=nil
local fakeRestoreTimeoutTime=nil

--For Google IAP only...
--Indicates whether the store has been initialised (for handling asynchronous initialisation on Google IAP
local storeInitialized = nil
--Once the store is initialised, run a restore
local initQueue = nil
local googleLastPurchaseProductID = ""
--On Google, if a purchase fails because the user already owns the item, convert the 'fail' state to success
local googleConvertOwnedPurchaseEvents = true

--Flag to indicate if this is the first item following a restore call
local firstRestoredItem=nil
--Action type - either "purchase" or "restore".  Used for faking Google purchase or restore
local actionType=nil

--List of products / prices returned by the loadProducts function.  If no product catalogue is available,
--the loadProductsCatalogue will contain "false" after the loadProducts function has been called (nil beforehand)
local loadProductsCatalogue=nil
    --Accessor function for getting at the catalogue
    local function getLoadProductsCatalogue() return loadProductsCatalogue end
    public.getLoadProductsCatalogue = getLoadProductsCatalogue

local loadProductsFinished=nil
    local function getLoadProductsFinished() return loadProductsFinished end
    public.getLoadProductsFinished = getLoadProductsFinished

-- Save the translated product identifier for reuse
local savedProductIdentifier

local logVerbose = function(msg)
    if verboseDebugOutput then
        print(msg)
    end
end

--Returns number of items in table, where the table may have holes in it
local tableCount = function(src)
    local count = 0
    if( not src ) then return count end
    for k,v in pairs(src) do
        count = count + 1
    end
    return count
end

--Debug table print function - this just prints the given table in a more human readable form
local debugPrint = function(t)
        local print_r_cache={}
        local function sub_print_r(t,indent)
                if (print_r_cache[tostring(t)]) then
                        print(indent.."*"..tostring(t))
                else
                        print_r_cache[tostring(t)]=true
                        if (type(t)=="table") then
                                for pos,val in pairs(t) do
                                        if (type(val)=="table") then
                                                print(indent.."["..pos.."] => {")
                                                sub_print_r(val,indent..string.rep(" ",string.len(pos)+2))
                                                print(indent..string.rep(" ",string.len(pos)+2).."}")
                                        elseif (type(val)=="string") then
                                                print(indent.."["..pos..'] => "'..val..'"')
                                        else
                                                print(indent.."["..pos.."] => "..tostring(val))
                                        end
                                end
                        else
                                print(indent..tostring(t))
                        end
                end
        end
        if (type(t)=="table") then
                print("{")
                sub_print_r(t," ")
                print("}")
        else
                sub_print_r(t," ")
        end
        print()
end

-- ***********************************************************************************************************

--Load/Save functions, based on Rob Miracle's simple table load-save functions.
--Inventory adds a layer of protection to the load/save functions.

local json = require("json")
local DefaultLocation = system.DocumentsDirectory
local RealDefaultLocation = DefaultLocation
local ValidLocations = {
   [system.DocumentsDirectory] = true,
   [system.CachesDirectory] = true,
   [system.TemporaryDirectory] = true
}

local function tableIsEmpty (self)
    if (self==nil) then return true end
    for _, _ in pairs(self) do
        return false
    end
    return true
end

local function saveToString(t)

    local contents = json.encode(t)
    --If a salt was specified, add a hash to the start of the data.
    --Only include a salt if a non-empty table was provided
    if (salt~=nil) and (tableIsEmpty(t)==false) then
        --Create hash
        local hash = crypto.digest(crypto.md5, salt .. contents)
        --Append to contents
        contents = hash .. contents
    end

    return contents

end

local function saveTable(t, filename, location)
    if location and (not ValidLocations[location]) then
     print("[IAP Badger] Attempted to save a table to an invalid location")
    elseif not location then
      location = DefaultLocation
    end

    local path = system.pathForFile( filename, location)
    local file = io.open(path, "w")
    if file then
        local contents = saveToString(t)
        file:write( contents )
        io.close( file )
        return true
    else
        return false
    end
end

local function loadInventoryFromString(contents)

    --If the contents start with a hash...
    if (contents:sub(1,1)~="{") then
        --Find the start of the contents...
        local delimeter = contents:find("{")
        --If no contents were found, return an empty table whatever the hash
        if (delimeter==nil) then return nil end
        local hash = contents:sub(1, delimeter-1)
        contents = contents:sub(delimeter)
        --Calculate a hash for the contents
        local calculatedHash = nil
        if (salt) then
            calculatedHash = crypto.digest(crypto.md5, salt .. contents)
        else
            calculatedHash = crypto.digest(crypto.md5, contents)
        end
        --If the two do not match, reject the file
        if (hash~=calculatedHash) then
            if (badHashResponse=="emptyInventory") then
                return nil
            elseif (badHashResponse=="errorMessage") then
                native.showAlert("Error", "File error.", {"Ok"})
                return nil
            elseif (badHashResponse=="error" or badHashResponse==nil) then
                print("[IAP Badger] File error occurred ***")
                return nil
            else
                badHashResponse()
                return nil
            end
        end
    end

    return json.decode(contents);

end

local function loadTable(filename, location)
    if location and (not ValidLocations[location]) then
     print("[IAP Badger] ERROR attempted to load a table from an invalid location ***")
    elseif not location then
      location = DefaultLocation
    end
    local path = system.pathForFile( filename, location)
    local contents = ""
    local myTable = {}
    local file = io.open( path, "r" )
    if file then
        -- read all contents of file into a string
        local contents = file:read( "*a" )
        myTable = loadInventoryFromString(contents)
        io.close( file )
        return myTable
    end
    return nil
end

local function changeDefaultSaveLocation(location)
    if location and (not location) then
        print("[IAP Badger] ERROR Attempted to change the default location to an invalid location ***")
    elseif not location then
        location = RealDefaultLocation
    end
    DefaultLocation = location
    return true
end

-- ***********************************************************************************************************

local function printInventory()
    print (json.encode(inventory))
end
public.printInventory = printInventory

--Searches for the inventory item with the given name in the refactor table.  If it does not exist, then nil is returned.
local function findNameInRefactorTable(name)

    --If no refactor table is available, just return the name that was passed - there is no refactoring to be done
    if (refactorTable==nil) then return nil end

    --For every item in the table
    for key, value in pairs(refactorTable) do
        if (value.name==name) then return value end
    end

    return nil
end


--Searches for the inventory item with the given refactored name in the refactor table.  If it does not exist, then nil is returned.
local function findRefactoredNameInRefactorTable(rName)

    --If no refactor table is available, just return the name that was passed - there is no refactoring to be done
    if (refactorTable==nil) then return nil end

    --For every item in the table
    for key, value in pairs(refactorTable) do
        if (value.refactoredName==rName) then return value end
    end

    return nil

end


--Refactors the given property
--  rObject - object from the refactor table describing how to refactor all of the properties
--  property - the name of the property to refactor
--  value - the value to refactor
--Returns: refactoredPropertyName, refactoredPropertyValue
local function refactorProperty(rObject, propertyName, propertyValue)

    --If there is no property information in the table, return the values that were given (there
    --is no refactoring to be done)
    if (rObject.properties==nil) then return propertyName, propertyValue end

    --Loop through the properties refactoring information to find the property
    for key, value in pairs(rObject.properties) do
        --If this is the key specified by the user...
        if (value.name==propertyName) then
           --Refactor the property name (if one was given)
           local refactoredName = propertyName
           if (value.refactoredName~=nil) then refactoredName=value.refactoredName end
           --Refactor the value (if a function is provided)
           local refactoredValue = propertyValue
           if (value.refactorFunction~=nil) then refactoredValue = value.refactorFunction(propertyValue) end
           --Return the values
           return refactoredName, refactoredValue
        end
    end

    --There is no information describing how to refactor this property, so return the values
    --that were given
    return propertyName, propertyValue

end

--Defactors the given property
--  rObject - object from the refactor table describing how to refactor all of the properties
--  property - the name of the property to defactor
--  value - the value to defactor
--Returns: defactoredPropertyName, defactoredPropertyValue
local function defactorProperty(rObject, propertyName, propertyValue)

    --If there is no property information in the table, return the values that were given (there
    --is no refactoring to be done)
    if (rObject.properties==nil) then return propertyName, propertyValue end

    --Loop through the properties refactoring information to find the property
    for key, value in pairs(rObject.properties) do
        --If this is the key specified by the user...
        if (value.refactoredName==propertyName) then
           --Defactor the property name (if one was given)
           local defactoredName = propertyName
           if (value.name~=nil) then defactoredName=value.name end
           --Defactor the value (if a function is provided)
           local defactoredValue = propertyValue
           if (value.defactorFunction~=nil) then defactoredValue = value.defactorFunction(propertyValue) end
           --Return the values
           return defactoredName, defactoredValue
        end
    end

    --There is no information describing how to refactor this property, so return the values
    --that were given
    return propertyName, propertyValue

end


--Creates a recfactored inventory
local function createRefactoredInventory()

    --If the refactor table is nil, return the inventory
    if (refactorTable==nil) then return inventory end

    --Create a new table that will be copy of the inventory table
    local refactoredInventory = {}

    for key, values in pairs(inventory) do

        --Store the key and value
        local refactoredName=key
        local refactoredValues=values

        --Does the inventory item exist in the refactor table>
        local refactorObject = findNameInRefactorTable(key)

        --If it does, then refactor
        if (refactorObject~=nil) then
            --Change the name of the object
            if (refactorObject.refactoredName~=nil) then refactoredName = refactorObject.refactoredName end
            --Iterate through the properties
            for pKey, pValue in pairs(values) do
                --Spare table to hold refactored values
                refactoredValues={}
                --Refactor
                local refactoredPropertyKey, refactoredPropertyValue = refactorProperty(refactorObject, pKey, pValue)
                refactoredValues[refactoredPropertyKey]=refactoredPropertyValue
            end
        end

        --Add the refactored information into the new inventory
        refactoredInventory[refactoredName] = refactoredValues
    end


    return refactoredInventory
end
public.createRefactoredInventory = createRefactoredInventory

--Creates a defactored inventory -- not sure if that's a real word, but there you go
local function createDefactoredInventory(inventoryIn)

    --Create a new table that will be copy of the inventory table
    local defactoredInventory = {}

    for key, values in pairs(inventoryIn) do

        --Store the key and value
        local defactoredName=key
        local defactoredValues=values

        --Does the inventory item exist in the refactor table>
        local refactorObject = findRefactoredNameInRefactorTable(key)

        --If it does, then refactor
        if (refactorObject~=nil) then
            --Change the name of the object
            defactoredName = refactorObject.name
            --Iterate through the properties
            for pKey, pValue in pairs(values) do
                --Spare table to hold refactored values
                defactoredValues={}
                --Refactor
                local defactoredPropertyKey, defactoredPropertyValue = defactorProperty(refactorObject, pKey, pValue)
                defactoredValues[defactoredPropertyKey]=defactoredPropertyValue
            end
        end

        --Add the refactored information into the new inventory
        defactoredInventory[defactoredName] = defactoredValues
    end

    return defactoredInventory
end
public.createDefactoredInventory = createDefactoredInventory


--Goes through inventory, and enters random values for random-integer and random-decimal
--products
local function randomiseInventory()

    for key, value in pairs(inventory) do
        --Find the product in the product catalogue
        local product = catalogue.inventoryItems[key]
        --If the product is specified in the inventory...
        if (product) then
            --If the product type is random-integer...
            if (product.productType=="random-integer") then
                value.value=math.random(product.randomLow, product.randomHigh)
            elseif (product.productType=="random-decimal") then
                value.value=math.random(product.randomLow, product.randomHigh)+(1/(math.random(1,1000)))
            elseif (product.productType=="random-hex") then
                value.value=string.format("0x%x", math.random(product.randomLow, product.randomHigh))
            end
        end
    end
end

--Saves the inventory contents
--asString - if nil, the inventory will be saved on the user's device; if set to true,
--will return a string representing the inventory that can be used for saving the inventory elsewhere
--(ie. on the cloud etc.)
local function saveInventory(asString)
    --Ignore if no filename given
    if (filename==nil) then return end
    --Create random values for random products
    randomiseInventory()
    --Refactor the inventory
    local refactoredInventory = createRefactoredInventory()
    --Save contents
    if (asString==nil) then
        saveTable(refactoredInventory, filename)
    else if (asString==true) then
        return saveToString(refactoredInventory)
        end
    end
end
public.saveInventory = saveInventory

--Load in a previously saved inventory
--If inventoryString=nil, then the inventory will be loaded from the save file on the user's device.
--If a string is passed, the library will attempt to decode a text string containing the inventory - use
--this for loading from the cloud etc.
local function loadInventory(inventoryString)
    --If no filename set, ignore
    if (filename==nil) then return end
    --Attempt to load inventory
    local refactoredInventory=nil
    if (inventoryString==nil) then
        refactoredInventory = loadTable(filename)
    else
        refactoredInventory = loadInventoryFromString(inventoryString)
    end
    --If inventory does not exists, create one
    if (refactoredInventory==nil) then
        inventory={}
    else
        inventory=createDefactoredInventory(refactoredInventory)
    end
end
public.loadInventory = loadInventory


--Returns true if the specified product exists
local function checkProductExists(productName)
    --Does the product name exist in the product table?
    if (catalogue.products[productName]==nil) then return false else return true end
end
public.checkProductExists = checkProductExists

--Returns the value of the current product inside the inventory (eg. a quantity / boolean)
--If the item is not in the inventory, this returns nil.
local function getInventoryValue(productName)
    if (inventory[productName]==nil) then
        if catalogue.inventoryItems[productName] and catalogue.inventoryItems[productName].reportMissingAsZero then return 0 end
        return nil
    end
    return inventory[productName].value
end
public.getInventoryValue = getInventoryValue

--Returns true if the item is in the inventory
local function isInInventory(productName)
    return inventory[productName]
end
public.isInInventory = isInInventory

--Returns the count of different itemt types in the inventory
local function inventoryItemCount()
    local ctr=0
    if (inventory==nil) then return 0 end
    for key, value in pairs(inventory) do
        ctr=ctr+1
    end
    return ctr
end
public.inventoryItemCount = inventoryItemCount

--Returns true if inventory is empty
local function isInventoryEmpty()
    return inventoryItemCount()==0
end
public.isInventoryEmpty = isInventoryEmpty

--Empties the inventory, keeping any non-consumable items.
--  disposeAll (optional): set to true to remove non-consumables as well (default=false)
local function emptyInventory(disposeAll)

    --Disposing everything is easy
    if (disposeAll==true) then
        inventory={}
        return
    end

    --Loop through and dispose of everything except non-consumables
    for key, value in pairs(inventory) do
        if (catalogue.inventoryItems[key].productType~="non-consumable") then
            inventory[key]=nil
        end
    end
end
public.emptyInventory=emptyInventory


--Empties the inventory, keeping any consumable items
local function emptyInventoryOfNonConsumableItems()

    --Loop through and dispose of all non-consumables
    for key, value in pairs(inventory) do
        if (catalogue.inventoryItems[key].productType=="non-consumable") then
            inventory[key]=nil
        end
    end
end
public.emptyInventoryOfNonConsumableItems=emptyInventoryOfNonConsumableItems


--Adds a product to the inventory
--  productName = name of the product to add
--  addValue (optional, default=1 for consumables, true for non-consuambles)
local function addToInventory(productName, addValue)

    --Get the product type
    local productType = catalogue.inventoryItems[productName].productType

    --If non-consumable, always set product value to true
    if (productType=="non-consumable") then
        inventory[productName]={value=true}
        return
    end

    --Adding a consumable so use a quantity
    --Random vars also end up here, but they ignore the quantity anyway, so don't
    --worry about it

    --Assume a quantity of 1, if no value if passed
    if (addValue==nil) then addValue=1 end

    --Does the current item already exist in the inventory?
    local currentValue=getInventoryValue(productName)
    --The following will handle cases where the product quantity comes back as zero rather than nil
    --(because user has specified things that way).  Zero quantities indicate something slightly
    --different to 'missing' items, so reset value to nil.
    if (currentValue==0) then currentValue=nil end

    --If it doesn't, create an entry for the item and quit
    if (currentValue==nil) then
        inventory[productName]={value=addValue}
        return
    end

    --Add the quantity to the stores of the item that are already there
    inventory[productName].value=currentValue+addValue

end
public.addToInventory = addToInventory

--Returns true if product was removed, false if not
--  productName = product to remove
--  subValue (optional) - number of items to remove, defaults to 1.  Non-consumables are always removed.  If attempting to remove a consumable (for
--  some reason), then set subValue to true to force removal.  If this item is a consumable, use "all" to remove all of the item.
local function removeFromInventory(productName, subValue)

    --Get the product type
    local productType = catalogue.inventoryItems[productName].productType

    --If the object is non-consumable...
    if (productType=="non-consumable") then
        --...and the force flag is set to true...
        if (subValue==true) then
            --Remove item
            inventory[productName]=nil
            --Item was removed - non-consumable but user forced removal
            return true
        end
        --Item wasn't removed - it was non-consumable
        print("[IAP Badger] ************************************")
        print("[IAP Badger] ERROR removeFromInventory() attempt to remove non-consumable item (" .. productName .. ") from inventory")
        print("[IAP Badger] ************************************")
        return false
    end

    --If the object is a consumable...
    if (productType=="consumable") then
        --If no quantity is given, assume a quantity of 1
        if (subValue==nil) then subValue=1 end
        --Does the current item already exist in the inventory?
        local currentQuantity=getInventoryValue(productName)
        if (subValue=="all") then subValue=currentQuantity end
        --If there will be an underrun, signal the error
        if (currentQuantity<subValue) then
            print("[IAP Badger] ************************************")
            print("[IAP Badger] ERROR removeFromInventory() attempted to removed more " .. productName .. "(s) than available in inventory (attempted to remove " .. subValue .. " from " .. currentQuantity .. " available)")
            print("[IAP Badger] ************************************")
            return false
        end
        --Remove the item
        inventory[productName].value = currentQuantity-subValue
        --If there are none of the item left, remove it from the inventory
        if (inventory[productName].value==0) then inventory[productName]=nil end
        --Item was removed
        return true
    end

    --If got here, than removing a random item - always just completely remove from inventory
    inventory[productName]=nil
    return true

end
public.removeFromInventory = removeFromInventory

--Sets the value of the item in the inventory.  No type checking is done - this is left to the user.
--  productName: the product to set
--  value_in: the value to set it to
local function setInventoryValue(productName, value_in)

    if (inventory[productName]==nil) then
        inventory[productName]={ value = value_in }
    else
        inventory[productName].value = value_in
    end
end
public.setInventoryValue=setInventoryValue


local function copyTable(arg)
    local t = {}
    for key, value in pairs(arg) do
        t[key] = value
    end
    return t
end


--Forces the debug mode
--  mode = true/false
--  store = name of store to simulator (defaults to apple)
local function setDebugMode(mode, store)

    --Set debug mode
    debugMode=mode

    --Copy in the debug store (if one was specified, and running on the simulator).  Ignore this on devices.
    if (system.getInfo("environment")=="simulator") then
        if (store~=nil) then debugStore=store else debugStore="apple" end
        storeName = storeNames[debugStore]
    end

    --If running on a device, and in debug mode, then make sure user knows
    if (system.getInfo("environment")~="simulator") and debugMode==true then
        native.showAlert("Warning", "Running IAP Badger in debug mode on device", {"Ok"})
    end

end
public.setDebugMode=setDebugMode

--Google only
--This will consume all products in the product table, regardless of whether they are consumable or not
--This function does not nothing on all other platforms
local function consumeAllPurchases()

    --This only applies to Google on a device - ignore for all other configurations
    if targetStore~="google" then return end

    --If running on Google IAP, the store may not have been initialised at this point.  If it isn't ready, queue up the restore for when it is and quit now
    if  storeInitialized==false then
        --Tell store transaction listener to run a restore when the initialisation is finished
        item = {
            name="consumeAllPurchases",
            params={ }
        }
        initQueue[#initQueue+1]=item
        --Quit now
        return true
    end

    --Iterate through the product catalogue
    for key, product in pairs(catalogue.products) do
        --If this product has a google product ID associated with it...
        if (product.productNames.google) then
            --...consume it
            store.consumePurchase(product.productNames.google)
        end
    end

end
public.consumeAllPurchases = consumeAllPurchases

-- ************************************************************************************************************

--Returns the product name and product data from the catalogue, 
--for the product with the given app store id.
local function getProductFromIdentifier(id)
    --Search the product catalogue for the relevant target store - if running in the simulator, default to iOS.
    local searchStore=targetStore
    if (targetStore=="simulator") then searchStore=debugStore end

    local productName=nil
    local product=nil

    --For every item in the product catalogue
    for key, value in pairs(catalogue.products) do
        --If this product has a store product names table...
        if (value.productNames~=nil) then
            --If this product has an entry in the correct store for the item that has been purchased...
            local thisProdName = value.productNames[searchStore]
            local isSub = false; if value.isSubscription then isSub = true; end
            -- Amazon subscription product IDs are substrings of the termSku product ID
            if (thisProdName==id) or (searchStore=="amazon" and isSub and string.sub(thisProdName,1,#id)==id) then
                --Return the product name and the product info from the catalogue
                return key, value
            end
        end
    end

    return nil, nil
end

--Returns the correct app store identifier for the specified product name
local function getAppStoreID(productName)
    --Search for the relevant target store - if running in the simulator,
    --default to iOS.
    local searchStore=targetStore
    if (targetStore=="simulator") then searchStore=debugStore end

    --Return the correct ID for this product
    return catalogue.products[productName].productNames[searchStore]
end

--Determine if a product is a subscription
local function getIsSubscription(productNameOrID)
    if productNameOrID == nil then
        return false
    end
    local searchStore=targetStore
    if (targetStore=="simulator") then searchStore=debugStore end
    if searchStore == "google" or searchStore == "apple" or searchStore == "amazon" then
        -- First search for a product name match
        if catalogue.products[productNameOrID] ~= nil and catalogue.products[productNameOrID].isSubscription ~= nil then
            if catalogue.products[productNameOrID].isSubscription then
                logVerbose("[IAP Badger] Is subscription (" .. productNameOrID .. ") -> true" )
            else
                logVerbose("[IAP Badger] Is subscription (" .. productNameOrID .. ") -> false" )
            end
            return catalogue.products[productNameOrID].isSubscription
        else
            -- Not a product name, search for a product ID match
            for pName, pProd in pairs(catalogue.products) do
                if pProd.productNames ~= nil then
                    local thisProdName = pProd.productNames[searchStore]
                    -- Amazon subscription product IDs are substrings of the termSku
                    if (thisProdName == productNameOrID) or (searchStore=="amazon" and string.sub(thisProdName,1,#productNameOrID)==productNameOrID) then
                        if catalogue.products[pName].isSubscription then
                            logVerbose("[IAP Badger] Is subscription (" .. productNameOrID .. ") -> true" )
                        else
                            logVerbose("[IAP Badger] Is subscription (" .. productNameOrID .. ") -> false" )
                        end
                        return catalogue.products[pName].isSubscription
                    end
                end
            end
            logVerbose("[IAP Badger] Is subscription (" .. productNameOrID .. ") -> false" )
            return false
        end
    end 
end

local function checkPreviousTransactionsForProduct(productIdentifier, transactionIdentifier)
    --If the table is empty, return false
    if (previouslyRestoredTransactions==nil) then
        return false
    end

    --Iterate over the table
    for key, value in pairs(previouslyRestoredTransactions) do
        --If this is the item specified...
        if (value.productIdentifier==productIdentifier) and
            (value.transactionIdentifier==transactionIdentifier) then
            --... indicate item found
            return true
        end
    end

    --Item wasn't found
    return false
end

local function executeInitQueue()

    --If the queue contains something...
    if initQueue~=nil then
        for key, item in pairs(initQueue) do
            --Load products
            if item['name']=="loadProducts" then
                loadProducts(item['params']['callback'])
            end
            --Restore
            if item['name']=="restore" then
                restore(item['params']['emptyFlag'], item['params']['postRestoreListener'], item['params']['timeoutFunction'], item['params']['cancelTime'])
            end
            --ConsumeAllPurchases
            if item['name']=="consumeAllPurchases" then consumeAllPurchases() end
            --Purchase
            if item['name']=="purchase" then purchase(item['params']['productList'], item['params']['listener']) end
        end
    end

    --Delete queue
    initQueue = {}

end

local URLencode = function(str)
    if (not str) then
        return str
    end
    str = string.gsub (str, "\n", "\r\n")
    str = string.gsub (str, "[^%w.%-_~]", function (c) return string.format ("%%%02X", string.byte(c)) end)
    return str
end

-- Receipt callback listener
verifyReceiptListener = function(event)
    local verified = false
    local responseObject = nil
    local product = nil
    local productName = nil
    local transaction = nil
    local token = nil
    if (event.isError) then
        logVerbose("[IAP Badger] ERROR in call to verification server; response: ")
        debugPrint(event.response)
    else
        logVerbose("[IAP Badger] Call to verification server is OK; response: ")
        debugPrint(event.response)
        if event.response ~= nil then
            responseObject = json.decode(event.response)
            if responseObject ~= nil then
                for aIndex,aState in pairs(asyncState) do
                    if aState.token == responseObject.token then
                        token = responseObject.token
                        product = aState.product
                        productName = aState.productName
                        transaction = aState.transaction
                        logVerbose("[IAP Badger] Found saved async state for token " .. token)
                        asyncState[aIndex] = nil
                    end
                end
            end
        end

        if product == nil then
            print("[IAP Badger] ERROR Did not find saved async state for this token - stopping receipt verification")
            if token ~= nil then
                print("[IAP Badger] Token not found is: " .. token)
            end
            return
        end

        -- Check if the server says receipt is valid
        if responseObject ~= nil then
            -- Amazon receipts contain the actual product purchased
            if responseObject.term_sku ~= nil then
                local skuName, skuProduct = getProductFromIdentifier(responseObject.term_sku)
                if skuName ~= nil then
                    productName = skuName
                    product = skuProduct
                end
            end
            if responseObject.valid ~= nil and tonumber(responseObject.valid) == 1 then
                logVerbose("[IAP Badger] Receipt is valid")
                verified = true
                if responseObject.sub_end_date ~= nil and responseObject.sub_end_date > 0 then
                    transaction.subscriptionEndDate = responseObject.sub_end_date
                    logVerbose("[IAP Badger] Found sub end date: " .. responseObject.sub_end_date)
                end
            else
                logVerbose("[IAP Badger] ERROR Receipt not valid")
            end
        else
            print("[IAP Badger] ERROR Could not verify receipt: event response was null")
        end

        if verified == true then
            --Valid receipt, call the user specified purchase function
            if (product.onPurchase~=nil) then
                logVerbose("[IAP Badger] Calling user defined purchase listener")
                product.onPurchase(productName, transaction)
                logVerbose("[IAP Badger] Returned from user defined purchase listener")
            end
            --Valid receipt, call the user specified listener to call after this transaction
            if (transaction.state=="purchased") and (postStoreTransactionCallbackListener~=nil) then
                logVerbose("[IAP Badger] Calling user defined purchase listener")
                postStoreTransactionCallbackListener(productName, transaction)
                logVerbose("[IAP Badger] Returned from user defined purchase listener")
            end
        else
            print("[IAP Badger] Receipt verification failed; not calling purchase listeners")
        end
    end
    logVerbose("[IAP Badger] verifyReceiptListener is done")
end

-- Make a call to the back end receipt verification service
verifyReceipt = function(store, product, productName, transaction)
    if receiptVerifyURL == nil then
        print("[IAP Badger] ************************************")
        print("[IAP Badger] ERROR cannot make call to receipt verification service, receiptVerifyURL is blank")
        print("[IAP Badger] ************************************")
        return
    end
    local newState = {}
    if store == "google" then
        newState.token = transaction.token
    end
    if store == "amazon" then
        newState.token = transaction.identifier
    end
    newState.product = product
    newState.productName = productName
    newState.transaction = transaction
    table.insert(asyncState, newState)
    logVerbose("[IAP Badger] Saved async state for token " .. newState.token)
    local productID = transaction.productIdentifier
    local params = {
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded"
        },
        body = "store=" .. store .. "&type=subscription" .. "&app=" .. URLencode(packageName) .. "&product=" .. URLencode(productID)
    }
    if (store == "google") then
        local token = transaction.token
        params.body = params.body .. "&token=" .. URLencode(token)
    end
    if (store == "amazon") then
        local userid = transaction.userId
        local receiptid = transaction.identifier
        params.body = params.body .. "&userid=" .. URLencode(userid) .. "&receiptid=" .. URLencode(receiptid)
    end
    logVerbose("[IAP Badger] Posting to URL: " .. receiptVerifyURL)
    logVerbose("[IAP Badger] Body: " .. params.body)
    network.request(receiptVerifyURL, "POST", verifyReceiptListener, params)
end

--Transaction callback for all purchase / restore functions
storeTransactionCallback = function(event)

    if (verboseDebugOutput) then
        print("[IAP Badger] storeTransactionCallback")
        print("[IAP Badger] event contains raw data:")
        debugPrint(event)
    end

    --If this is an init callback (Google IAP)...
    if (event.name == "init") then
        logVerbose("[IAP Badger] Initialisation event")
        --Record store is initialised
        storeInitialized=true
        --Work through items in the queue waiting to be executed
        logVerbose("[IAP Badger] Store initialised, executing timed commands on a 50ms timer...")
        timer.performWithDelay(50, executeInitQueue)
        --Quit now - event has been processed
        logVerbose("[IAP Badger] Leaving storeTransactionCallback")
        return true
    end

    --Consumption events need no action
    if (event.name=="storeTransaction") and (event.transaction.state=="consumed") then
        if (verboseDebugOutput) then
            print("[IAP Badger] Consumption notification event")
            print("[IAP Badger] Leaving storeTransactionCallback")
        end
        return
    end

    --restoreCompleted events need no action
    if (event.name=="storeTransaction") and (event.transaction.state=="restoreCompleted") then
        if (verboseDebugOutput) then
            print("[IAP Badger] RestoreCompleted notification event")
            print("[IAP Badger] Leaving storeTransactionCallback")
        end
        return
    end

    logVerbose("[IAP Badger] Store transaction event")

    --Get a copy of the transaction
    local transaction={}
    --Make a local copy of the transaction
    --Put in empty values for missing variables in the transaction table
    local transaction_vars = {
        "cancelDate",
        "date",
        "errorString",
        "errorType",
        "identifier",
        "isError",
        "marketplace",
        "originalDate",
        "originalIdentifier",
        "originalReceipt",
        "packageName",
        "productIdentifier",
        "receipt",
        "signature",
        "state",
        "subscriptionEndDate",
        "subscriptionStartDate",
        "token",
        "transactionIdentifier",
        "userId"
    }
    --From the real transaction, copy in any passed value over those null strings
    for key, value in pairs(transaction_vars) do
        if event.transaction and event.transaction[value] then
            transaction[value]=event.transaction[value]
        else
            transaction[value]=""
        end
    end

    if (transaction.state=="") then
        transaction.state="failed"
        transaction.errorString = "Error accessing " .. targetStore
        transaction.isError = true
        transaction.errorType = 0
    end

    --If on the Google or Amazon store, and the last action from the user was to make a restore, and this
    --appears to be a purchase, then convert the event into a restore
    if ( ((targetStore=="amazon") or targetStore=="google")) and (actionType=="restore") and (transaction.state=="purchased") then
        transaction.state="restored"
        logVerbose("[IAP Badger] Converting " .. targetStore .. " purchase event into a restore event")
    end

    --If on the Amazon store, the revoked status is equivalent to refunded
    if (targetStore=="amazon") and (transaction.state=="revoked") then
        logVerbose("[IAP Badger] Converting Amazon revoked event into refunded event")
        transaction.state="refunded"
    end

    -- Google Play errorType 6 means "failed, retry"
    -- See: https://developer.android.com/reference/com/android/billingclient/api/BillingClient.BillingResponseCode#ERROR()
    -- As a precaution against converting failed transactions into successful purchases, we try to consume the product here
    if targetStore=="google" and transaction.state=="failed" and transaction.errorType ~= nil and transaction.errorType==6 then
        retryCount = retryCount + 1
        if retryCount <= 3 then
            logVerbose("[IAP Badger] Consuming Google product as failsafe for failed transaction.")
            if (savedProductIdentifier) then
                print( "[IAP Badger] savedProductIdentifier = " .. savedProductIdentifier )
                timer.performWithDelay(100*retryCount, function()
                    logVerbose("[IAP Badger] Calling consumePurchase now")
                    store.consumePurchase(savedProductIdentifier)
                    if (debugMode~=true) then store.finishTransaction(event.transaction) end
                end)
            else
                print( "[IAP Badger] savedProductIdentifier is nil - cannot call consumePurchase" )
            end
        else
            logVerbose("[IAP Badger] Maximum retryCount reached; giving up")
        end
        return true
    end
    retryCount = 0

    -- If on Google Play, and this purchase failed because the user already owns the item, convert the failed event into a restore event
    -- See: https://developer.android.com/reference/com/android/billingclient/api/BillingClient.BillingResponseCode#ITEM_ALREADY_OWNED()
    if targetStore=="google" and transaction.state=="failed" and transaction.errorType ~= nil and transaction.errorType==7 then
        --If converting these events to successful events (like on iOS)...
        if googleConvertOwnedPurchaseEvents then
            if getIsSubscription(googleLastPurchaseProductID) == false then
                --Set the new transaction state
                transaction.state="purchased"
                transaction.isError=false
                transaction.errorType=0
                transaction.errorString=""

                --Set the product idenitfier
                transaction.productIdentifier = googleLastPurchaseProductID
                --Logging
                if (verboseDebugOutput) then
                    print("[IAP Badger] User already owns item. Converting FAILED event into a PURCHASED event")
                    print("[IAP Badger] New event data:")
                    debugPrint(transaction)
                end
            else
                print("[IAP Badger] User already owns item, however subscriptions cannot be converted to purchase events because the token is missing")
            end
        else
            if (verboseDebugOutput) then
              print("[IAP Badger] User already owns item.  PURCHASE event failed.")
            end
        end
    end

    --Reset last google purchase product name
    googleLastPurchaseProductID=""

    --Search the product catalogue for the relevant target store - if running in the simulator,
    --default to iOS.
    local searchStore=targetStore
    if (targetStore=="simulator") then searchStore=debugStore end

    --Check product name if not a failed or cancelled event
    --Find the product by using its identifier in the product catalogue
    if (verboseDebugOutput) then
        print ("[IAP Badger] Converting store product ID " .. transaction.productIdentifier .. " to catalogue product name.")
    end
    local productName, product = getProductFromIdentifier(transaction.productIdentifier)
    if (verboseDebugOutput) and (productName~=nil) then
        print ("[IAP Badger]  " .. transaction.productIdentifier .. " ==> " .. productName)
    end

    --If this is NOT a 'failed' or 'cancelled' event, handle invalid product IDs
    if (transaction.state~="failed") and (transaction.state~="cancelled") then
        --At this point, we could be in a purchase, refund or restored transaction - so a product ID is essential
        --If the product has not been identified, something has gone wrong
        if (product==nil) then
            --Does the library need to raise product ID errors?  Assume yes
            local raiseProductIDError=true
            --But... in test mode, IAP Badger does use a dummy product ID to simulate cancelled and failed purchases, so ignore those
            if (debugMode and (transaction.productIdentifier=="debugProductIdentifier")
                and ((transaction.state=="failed") or (transaction.state=="cancelled")) ) then
                raiseProductIDError=false
            end
            --Raise product ID error
            if (raiseProductIDError) then
                --If user has requested invalid IDs to be ignored during a restore event...
                if (handleInvalidProductIDs) and (transaction.state=="restored") then
                    if (verboseDebugOutput) then
                        --Let them know this has happened
                        print("[IAP Badger] ************************************")
                        print("[IAP Badger] ERROR storeTransactionCallback() unable to find product '" .. transaction.productIdentifier .. "' in a product for the " ..
                            targetStore .. " store")
                        print("[IAP Badger] Ignoring restore for this product.")
                        print("[IAP Badger] ************************************")
                    end
                    if (debugMode~=true) then store.finishTransaction(event.transaction) end
                    return true
                end
                print("[IAP Badger] ************************************")
                print("[IAP Badger] ERROR storeTransactionCallback() unable to find product '" .. transaction.productIdentifier .. "' in a product for the " ..
                    targetStore .. " store")
                print("[IAP Badger] Unable to process transaction event.")
                print("[IAP Badger] ************************************")
                return false
            end
        end
    end

    ---------------------------------
    -- Handle refunds (Android-based machines only)
    -- Refunds always follow a call to store.restore(); refunds should be silent, and will not initiate any callback.

    --Refunds on Amazon
    --  An amazon refund (revoke) can follow a restore callback - in which case, the refund should be ignored.
    if (targetStore=="amazon") and (transaction.state=="refunded") then
            logVerbose("[IAP Badger] Handling Amazon refund")
        --Check through the previously restored transactions to see if this product is listed
        if (checkPreviousTransactionsForProduct(transaction.productIdentifier, transaction.transactionIdentifier)==true) then
            --Just ignore this revoke - the user has previously revoked, repurchased and then restored the item
            if (debugMode~=true) then store.finishTransaction(event.transaction) end
            logVerbose("[IAP Badger] Leaving storeTransactionCallback")
            return true
        end
    end
    --All refunds should be silent
    if (transaction.state=="refunded") then
        logVerbose("[IAP Badger] Handling refunded event")
        --User callback
        if (product.onRefund~=nil) then product.onRefund(productName, transaction) end
        --Tell the store we're finished
        if (debugMode~=true) then store.finishTransaction(event.transaction) end
        --Return
        logVerbose("[IAP Badger] Leaving storeTransactionCallback")
        return true
    end


    ------------------------------
    -- The other transaction states (failed, cancelled, purchase, restore) can be noisy
    -- so cancel any restore purchases cancel timer.

    if (restorePurchasesTimer~=nil) then
        timer.cancel(restorePurchasesTimer)
        restorePurchasesTimer=nil
    end

    ------------------------------
    -- Deal with problems first

    --Failed transactions
    if (transaction.state=="failed") then
        logVerbose("[IAP Badger] Transaction FAILED")
        if (transactionFailedListener~=nil) then
            logVerbose("[IAP Badger] Calling failed listener")
            transactionFailedListener(productName, event.transaction)
            logVerbose("[IAP Badger] Returned from failed listener")
        else
            native.showAlert("Error", "Transaction failed: " .. transaction.errorString, {"Ok"})
        end
        --Tell the store we are finished
        if (debugMode~=true) then store.finishTransaction(event.transaction) end
        logVerbose("[IAP Badger] Leaving storeTransactionCallback")
        return true
    end

    --User cancelled transaction
    if (transaction.state=="cancelled") then
        logVerbose("[IAP Badger] Transaction CANCELLED BY USER")
        if (transactionCancelledListener~=nil) then
            logVerbose("[IAP Badger] Calling cancel listener")
            transactionCancelledListener(productName, event.transaction)
            logVerbose("[IAP Badger] Returned from cancel listener")
        else
            native.showAlert("Information", "Transaction cancelled by user.", {"Ok"})
        end
        --Tell the store we are finished
        if (debugMode~=true) then store.finishTransaction(event.transaction) end
        logVerbose("[IAP Badger] Leaving storeTransactionCallback")
        return true
    end

    if (transaction.state=="finished") then
      if (debugMode~=true) then store.finishTransaction(event.transaction) end
      logVerbose("[IAP Badger] Finished - leaving storeTransactionCallback")
        return true
    end

    ------------------------------
    --If the program gets this far into the function, the product was purchased, restored or refunded.

    if (verboseDebugOutput) then
        if (transaction.state=="restored") then
            print("[IAP Badger] Processing RESTORE event")
        else
            print("[IAP Badger] Processing PURCHASE event")
        end
    end

    --If this is a restore callback, and this is the first item to be restored...
    if (firstRestoredItem==true) and (transaction.state=="restored") then
        logVerbose("[IAP Badger] Recording that this is the FIRST RESTORE item")
        --Add a flag to the transaction event that tells the user
        transaction.firstRestoreCallback=true
        --Reset the flag
        firstRestoredItem=nil
    end

    --If successfully purchasing or restoring a transaction...
    if (transaction.state=="purchased") or (transaction.state=="restored") then
        local receiptVerificationInProgress = false
        local isSubscription = getIsSubscription(productName)

        -- Apple subscriptions can use the receipt data to determine subscription end date
        local appleReceiptData = nil
        transaction.subscriptionEndDate = 0
        if isSubscription and targetStore == "apple" then
            if store.receiptAvailable() then
                appleReceiptData = store.receiptDecrypted()
                if appleReceiptData ~= nil and appleReceiptData.in_app ~= nil then
                    logVerbose("[IAP Badger] ----------- Receipt Start ---------")
                    local maxExpiresDate = 0
                    for ri, receiptDetails in ipairs(appleReceiptData.in_app) do
                        if receiptDetails.product_id == product.productNames.apple then
                            logVerbose("[IAP Badger] Receipt #" .. ri .. " for: " .. receiptDetails.product_id .. " expires=" .. receiptDetails.expires_date)
                            if receiptDetails.expires_date > maxExpiresDate and receiptDetails.cancellation_date == 0 then
                                maxExpiresDate = receiptDetails.expires_date
                            end
                        else
                            logVerbose("[IAP Badger] Ignoring receipt for: " .. receiptDetails.product_id)
                        end
                    end
                    logVerbose("[IAP Badger] ----------- Receipt End ---------")
                    transaction.subscriptionEndDate = maxExpiresDate
                else
                    print("[IAP Badger] ************************************")
                    print("[IAP Badger] ERROR plugin.apple.iap.helper and plugin.openssl must be added to build.settings to support subscriptions on Apple")
                    print("[IAP Badger] ************************************")
                end
            end
        end

        -- Google subscriptions require server side verification to determine subscription end date
        if isSubscription and targetStore == "google" then
            if transaction.receipt ~= nil then
                if receiptVerifyURL ~= nil then
                    logVerbose("[IAP Badger] Starting async Google subscription receipt verification")
                    receiptVerificationInProgress = true
                    verifyReceipt("google", product, productName, transaction)
                else
                    print("[IAP Badger] ************************************")
                    print("[IAP Badger] ERROR receiptVerifyURL must be supplied during init for Google subscription receipt verification")
                    print("[IAP Badger] ************************************")
                end
            else
                print("[IAP Badger] ************************************")
                print("[IAP Badger] ERROR Receipt data was blank")
                print("[IAP Badger] ************************************")
            end
        end

        -- Amazon subscriptions require server side verification to determine subscription end date
        if isSubscription and targetStore == "amazon" then
            if transaction.receipt ~= nil then
                if receiptVerifyURL ~= nil then
                    logVerbose("[IAP Badger] Starting async Amazon subscription receipt verification")
                    receiptVerificationInProgress = true
                    verifyReceipt("amazon", product, productName, transaction)
                else
                    print("[IAP Badger] ************************************")
                    print("[IAP Badger] ERROR receiptVerifyURL must be supplied during init for Amazon subscription receipt verification")
                    print("[IAP Badger] ************************************")
                end
            else
                print("[IAP Badger] ************************************")
                print("[IAP Badger] ERROR Receipt data was blank")
                print("[IAP Badger] ************************************")
            end
        end

        if isSubscription and targetStore == "simulator" then
            transaction.subscriptionEndDate = os.time() + 600 -- Simulator subscriptions last 5 minutes
        end

        --Call the user specified purchase function, only if receipt verification is not in progress
        if (product.onPurchase~=nil and receiptVerificationInProgress==false) then
            logVerbose("[IAP Badger] Calling user defined purchase listener")
            product.onPurchase(productName, transaction)
            logVerbose("[IAP Badger] Returned from user defined purchase listener")
        end
        --Tell the store we're finished. We finish this transaction to the store even if receipt
        --verification is in progress, otherwise the purchase could be refunded by the store.
        if (debugMode~=true) then 
            logVerbose("[IAP Badger] Calling finishTransaction now")
            store.finishTransaction(event.transaction) 
        end
        --If the user specified a listener to call after this transaction, call it only if
        --receipt verification is not in progress
        if (transaction.state=="purchased") and (postStoreTransactionCallbackListener~=nil) and (receiptVerificationInProgress==false) then
            logVerbose("[IAP Badger] Calling user defined purchase listener")
            postStoreTransactionCallbackListener(productName, transaction)
            logVerbose("[IAP Badger] Returned from user defined purchase listener")
        end

        --Restore events - only process for non-consumables unless instructed to by the user
        if (transaction.state=="restored") and (postRestoreCallbackListener~=nil) then
            --Default to processing the event
            local processEvent=true
            --Don't process consumables
            if (product.productType=="consumable") then processEvent=false end
            --Unless the user has overridden this in the product catalogue
            if (product.allowRestore) then processEvent=true end
            --Should event be processed?
            if (processEvent) then
                logVerbose("[IAP Badger] Calling user defined restore listener")
                postRestoreCallbackListener(productName, transaction)
                logVerbose("[IAP Badger] Returned from user defined restore listener")
            else
                --Tell user the event is being ignored
                logVerbose("[IAP Badger] Ignoring restore request, product is a consumable")
            end
        end
        --If running on Amazon, and this is a restore, save the purchase info (may need to cancel a revoke later)
        if (targetStore=="amazon") and (transaction.state=="restored") then
            previouslyRestoredTransactions[#previouslyRestoredTransactions+1]=transaction
        end
        --If this is a consumable, and running on Google Play, immediate consume the item so it can be purchased again
        if (targetStore=="google") and (product.productType=="consumable") then
            logVerbose("[IAP Badger] Running Android consumePurchase event on timer")
            --Run this on a timer - not recommended to consume purchases within the IAP listener
            --Increased from 10ms to 500ms, otherwise multi-quantity purchases failed to complete in time
            timer.performWithDelay(500, function() 
                logVerbose("[IAP Badger] Calling consumePurchase now")
                store.consumePurchase(transaction.productIdentifier)
            end)
        end
        logVerbose("[IAP Badger] Leaving storeTransactionCallback")
        return true
    end

    logVerbose("[IAP Badger] Leaving storeTransactionCallback - DID NOT INDICATE SUCCESSFUL PROCESSING - SOMETHING WENT WRONG")
    return false
end


--Returns a list of available products
local function getProductList()

    local list = {}
    for key, value in pairs(catalogue.products) do
        list[#list+1]=key
    end
    return list

end

--Returns the current store name
local function getStoreName()
    return storeName
end
public.getStoreName = getStoreName

--Returns the target store
local function getTargetStore()
    return targetStore
end
public.getTargetStore = getTargetStore

--Returns the identifier for the given product name in the current store (ie. product identifier in iTunes Connect
--may be different to Google etc.)  So, in the catalogue, a product called buyExtraLife might return BUY_LIFE if user
--is buying on iOS through iTunes Connect, or life_purchase on Google.
local function getProductIdentifierFromName(productName)
    if (onSimulator) then
        return catalogue.products[productName].productNames[debugStore]
    else
        return catalogue.products[productName].productNames[targetStore]
    end
end
public.getProductIdentifierFromName=getProductIdentifierFromName


--Restores purchases
--If this is on a real device, the function will contact the appropriate store to see if there are any purchases that need restoring.
--In debug mode, this will ask you which purchases you would like to restore.
--   emptyFlag - empty the inventory of non-consumable items before restoring from store
--   postRestoreListener (optional) - function to call after restore is complete
--   timeoutFunction (optional) = function to call after a given amount of time if this function hangs (store.restore does not return a transaction when
--        there are no transactions to restore.
--   cancelTime (optional): how long to wait in ms before calling timeoutFunction (default 10s)
restore=function(emptyFlag, postRestoreListener, timeoutFunction, cancelTime)

    logVerbose("[IAP Badger] Entering RESTORE")

    if (emptyFlag~=true) and (emptyFlag~=false) then
        print("[IAP Badger] ************************************")
        print("[IAP Badger] ERROR Restore called without setting emptyFlag to true or false (should non-consumables in inventory be removed before contacting store?) ***")
        print("[IAP Badger] ************************************")
        return
    end

    if not initDone then
        print("[IAP Badger] ERROR Cannot call restore() before calling init()")
        return
    end

    --If running on Google IAP, the store may not have been initialised at this point.  If it isn't ready, queue up the restore for when it is and quit now
    if ( (targetStore=="google") or ((targetStore=="simulator") and (debugStore=="google")) ) and (storeInitialized==false) then
        logVerbose("[IAP Badger] Google Play not initilialised yet - queuing restore")
        --Tell store transaction listener to run a restore when the initialisation is finished
        item = {
            name="restore",
            params={ emptyFlag = emptyFlag, postRestoreListener=nil, timeoutFunction=nil, cancelTime=nil }
        }
        if (postRestoreListener) then item['params']['postRestoreListener'] = postRestoreListener end
        if (timeoutFunction) then item['params']['timeoutFunction'] = timeoutFunction end
        if (cancelTime) then item['params']['cancelTime'] = cancelTime end
        initQueue[#initQueue+1]=item
        --Quit now
        logVerbose("[IAP Badger] Leaving restore")
        return true
    end

    --Set action type
    actionType="restore"

    --Save post restore listener
    postRestoreCallbackListener = postRestoreListener

    --Remove all non-consumable items from inventory - these will be restored by the relevant App Store
    if (emptyFlag==true) then emptyInventoryOfNonConsumableItems() end

    --If no time passed, use a reasonable time (10s)
    if (cancelTime==nil) then cancelTime=10000 end

    --store.restore does not provide a callback if there are no products to restore - the code
    --is just left hanging.  Call the userdefined timeoutFunction after the specified amount of
    --time has elapsed if this happens.

    --Set the 'first item callback after a restore' flag
    firstRestoredItem=true

    --Reset the previously restored transactions table
    previouslyRestoredTransactions={}

    --Initiate restore purchases with store
    if debugMode==true or onSimulator then
        logVerbose("[IAP Badger] On simulator/debug mode - faking restore")
        fakeRestoreTimeoutTime=cancelTime
        fakeRestoreTimeoutFunction=timeoutFunction
        fakeRestore()
    else
        logVerbose("[IAP Badger] Requesting restore...")
        --Start restore
        store.restore()
        --Set up a timeout if the user specified a timeoutFunction to call
        if (timeoutFunction~=nil) then
            logVerbose("[IAP Badger] Timeout function specified, placing on timer...")
            restorePurchasesTimer=timer.performWithDelay(cancelTime, function()
                --Kill the first restored item flag and fail callback pointer
                firstRestoredItem=nil
                restorePurchasesTimer=nil
                actionType=nil
                --Call the user defined timeout function
                logVerbose("[IAP Badger] Not heard anything back from restore yet, so calling user-defined timeout function.")
                timeoutFunction()
                logVerbose("[IAP Badger] Returned from user-defined timeout function for restore.")
            end)
        end
    end

    logVerbose("[IAP Badger] Leaving restore")

end
public.restore=restore


--Purchase function
--  productList: string or table of strings of items to purchase.  On Amazon, only a string is valid (Amazon only supports purchase of one item at a time)
--  listener (optional): function to call after purchase is successful/unsuccessful.  The function will be called with the transaction portion
--      of the store event.  ie. in the form: function(event) result=event.state (purchased, restored, failed, cancelled, refunded) end
purchase=function(productList, listener)

    if (verboseDebugOutput) then
        print("[IAP Badger] Entering PURCHASE")
        print("[IAP Badger] Purchasing productList:")
        debugPrint(productList)
    end

    if not initDone then
        print("[IAP Badger] ERROR Cannot call purchase() before calling init()")
        return
    end

    --If running on Google IAP, the store may not have been initialised at this point.  If it isn't ready, queue up the purchase for when it is and quit now
    if ( (targetStore=="google") or ((targetStore=="simulator") and (debugStore=="google")) ) and (storeInitialized==false) then
        logVerbose("[IAP Badger] Google Play not initialised - queuing purchase call")
        --Tell store transaction listener to run a restore when the initialisation is finished
        item = {
            name="purchase",
            params={ productList=productList, listener=nil }
        }
        if (listener) then item['params']['listener'] = listener end
        initQueue[#initQueue+1]=item
        --Quit now
        logVerbose("[IAP Badger] Leaving purchase")
        return true
    end

    --Save post purchase listener specified by user
    postStoreTransactionCallbackListener=listener

    --Kill the restore item flag if it has been set - attempting a purchase now
    firstRestoredItem=nil

    --Set action type
    actionType="purchase"

    --Convert string parameters into a table with a single element
    if (type(productList)=="string") then productList={ productList } end

    -------------------------------
    --Handle Amazon separately

    if (targetStore=="amazon") then
        --Parameter check (user can only pass a string, rather than a table of strings, as Amazon only supports purchases one item at a time)
        if (tableCount(productList)>1) then
            print("[IAP Badger] Purchase - attempted to pass more than one product to purchase on Amazon store (Amazon only supports purchase of one item at a time) ***")
        end
        --Convert the product from a catalogue name to a store name
        local renamedProduct = getAppStoreID(productList[1])
        --Purchase it
        if (debugMode==true) then
            --Convert back into a table for fake purchases
            local renamedProductList = { renamedProduct }
            logVerbose("[IAP Badger] On simulator/debug mode - faking purchase")
            fakePurchase(renamedProductList)
        else
            --Real store will want the name of the product as a string (and nothing else)
            logVerbose("[IAP Badger] Requesting purchase of " .. renamedProduct .. " from Amazon...")
            store.purchase(renamedProduct)
        end
        --Quit here
        logVerbose("[IAP Badger] Leaving purchase")
        return
    end

    -------------------------------
    --Handle Google IAP

    if (targetStore=="google") then
        --Parameter check (user can only pass a string, rather than a table of strings, as Google only supports purchases one item at a time)
        if (tableCount(productList)>1) then
            print("[IAP Badger] Purchase - attempted to pass more than one product to purchase on Google Play (IAP only supports one product purchase at a time) ***")
        end
        --Convert the product from a catalogue name to a store name
        local renamedProduct = getAppStoreID(productList[1])
        savedProductIdentifier = renamedProduct
        --Purchase it
        if (debugMode==true) then
            --Convert back into a table for fake purchases
            local renamedProductList = { renamedProduct }
            logVerbose("[IAP Badger] On simulator/debug mode - faking purchase")
            fakePurchase(renamedProductList)
        else
            --Real store will want the name of the product as a string (and nothing else)
            logVerbose("[IAP Badger] Requesting purchase from Google Play...")
            googleLastPurchaseProductID = renamedProduct
            if getIsSubscription(productList[1]) and targetStore == "google" then
                logVerbose("[IAP Badger] (Google) Calling purchaseSubscription ", renamedProduct)
                store.purchaseSubscription(renamedProduct)
            else
                logVerbose("[IAP Badger] (non-Google) Calling purchase ", renamedProduct)
                store.purchase(renamedProduct)
            end
        end
        --Quit here
        logVerbose("[IAP Badger] Leaving purchase")
        return
    end


    --------------------------------
    --Other stores (and debug mode) all support purchase of more than one item at a time...

    --Convert every item in the product list from a catalogue name to a store name
    local renamedProductList = {}
    for key, value in pairs(productList) do
        local productID = getAppStoreID(value)
        renamedProductList[#renamedProductList+1]=productID
    end

    --Make purchase
    if (debugMode==true) then
        logVerbose("[IAP Badger] On simulator/debug mode - faking purchases")
        fakePurchase(renamedProductList)
    else
        logVerbose("[IAP Badger] Requesting purchase from Apple...")
        store.purchase(renamedProductList)
    end

    logVerbose("[IAP Badger] Leaving purchase")
end
public.purchase=purchase


--Initialises store
--  Options: table containing...
--      * catalogue = table containing a list of available products of items that appear in inventory
--      * filename = filename for inventory save file
--      * refactorTable (optional) = table containing refactor information
--      * salt (optional) = salt to use for hashing table contents
--      * failedListener (optional) = listener function to call when a transaction fails (in the form, function(itemName, transaction), where itemName=the item
--          the user was attempting to purchase, transaction = transaction info returned by Corona)
--      * cancelledListener (optional) = listener function to call when a transaction is cancelled by the user (in the form, function(itemName, transaction),
--          where itemName=the item the user started to purchase, transaction = transaction info returned by Corona)
--      (If no function for tFailedListener or tCancelledListener is specified, a simple message saying the transaction was cancelled or failed (with a reason)
--      is given.)
--      * badHashResponse (optional) - indicates what to do if someone has been messing around with the inventory file (ie. the hash does not match
--          the contents of the inventory file).  Legal values are:
--          * "errorMessage" for a simple "File error" message to be displayed to the user before emptying the inventory
--          * "emptyInventory" to display no message at all, other than the empty the inventory
--          * "error" to print an error message to the console and empty inventory (this may halt the program, depending on how your code is set up)
--          * function() end, a pointer to a user defined listener function to call when a bad hash is detected.
--          A bad hash will always result in the inventory being deleted.
--      * debugMode (optional) - set to true to start in debug mode
--      * debugStore (optional) - identify a store to use in debug mode (eg. "apple", "google").  Only valid on simulator
--      * doNotLoadInventory (optional) - set to true to start with an empty inventory (useful for debugging)
--      * verboseDebugOutput (optional) - sends lots of debugging info to the console
--      * handleInvalidProductIDs (optional) - set to true to ignore invalid product IDs during a restore event -  but tell the store they have been successfully processed.  This can be useful is a product ID for an app has been changed/deleted but some users still have products registered against them.  Default is false
--      * googleConvertOwnedPurchaseEvents (optional, affects Android only) - set to true to convert failing purchase events to successful ones, where the attempt failed because the user already owns the item, mimicking the flow on iOS.  Default is true.

local function init(options)

    --Some options are mandatory
    if (options==nil) then
        error("[IAP Badger] Init - no options table provided")
    end
    if (options.catalogue==nil) then
        error("[IAP Badger] Init - no catalogue provided")
    end
    if (options.package==nil) then
        error("[IAP Badger] Init - no package name provided")
    end

    --Verbose debug info?
    if (options.verboseDebugOutput) then
        verboseDebugOutput=true
        print("--------------------------------------------------------------------")
        print("IAP Badger: init")
        print("Running version: " .. version)
        print("Called with options: ")
        debugPrint(options)
        print("")
        print("VerboseDebugOutput set to true")
    end

    --Converting Google failed purchase events to successful events (when purchase events fail because the user already owns the item, like on iOS)?
    --If the flag is set in the options...
    if (options.googleConvertOwnedPurchaseEvents~=nil) then
        --Set to true or false
        if (options.googleConvertOwnedPurchaseEvents) then
          googleConvertOwnedPurchaseEvents = true
        else
          googleConvertOwnedPurchaseEvents = false
        end
    end

    --Get a copy of the products table
    catalogue=options.catalogue
    packageName=options.package
    --Filename
    if (options.filename) then
        filename=options.filename
    end

    --Handle invalid product IDs?
    if (options.handleInvalidProductIDs) then
        handleInvalidProductIDs = options.handleInvalidProductIDs
        if (verboseDebugOutput) and (options.handleInvalidProductIDs) then
            print("[IAP Badger] handleInvalidProductIDs flag set, will handle invalid product IDs during restore events.")
        end
    end

    --Refactor table (optional)
    refactorTable=options.refactorTable
    --Load in the salt (optional)
    salt=options.salt
    --Bad hash response
    if (options.badHashResponse~=nil) then badHashResponse=options.badHashResponse end
    --Transaction failed / cancelled listeners (both optional)
    transactionFailedListener = options.failedListener
    transactionCancelledListener = options.cancelledListener

    --Load in inventory
    if (options.doNotLoadInventory==true) then
        inventory={}
    else
        loadInventory()
    end

    --On device or simulator?
    onSimulator = (system.getInfo("environment")=="simulator")

    --Initalise store
    --Assume the store isn't available
    storeAvailable = false
    --Get the current device's target store
    targetStore = system.getInfo("targetAppStore")
    logVerbose ("[IAP Badger] Device target store identified as '" .. targetStore .. "'")

    --Give warnings about compiling with 'none' in the build dialog in Corona on Android (all IAPs will fail)
    if (targetStore=="none") and (system.getInfo("platform")=="android") then
      print("[IAP Badger] ************************************")
      print("[IAP Badger] ERROR No Android store is available. IAP will not work correctly. To fix, rebuild your app and specify a target app store.")
      print("[IAP Badger] ************************************")
    end

    --If running on the simulator, set the target store manually
    if onSimulator then
        targetStore="simulator"
        storeAvailable=true
        storeInitialized=true
        logVerbose("[IAP Badger] Running on simulator")
    end

    --Set receiptVerifyURL, and show an error if missing when needed
    if (options.receiptVerifyURL~=nil) then receiptVerifyURL=options.receiptVerifyURL end
    for key, product in pairs(catalogue.products) do
        if getIsSubscription(key) == true and receiptVerifyURL == nil and targetStore == "google" then
            print("[IAP Badger] ************************************")
            print("[IAP Badger] ERROR receiptVerifyURL must be set when target store is Google and some products are subscriptions.")
            print("[IAP Badger] ************************************")
        end
    end
    asyncState = {}

    --Initialise if the store is available
    if targetStore=="apple" then
        logVerbose("[IAP Badger] Running on iOS")
        store=require("plugin.apple.iap")
        store.init("apple", storeTransactionCallback)
        storeAvailable = true
        storeInitialized = true
    elseif targetStore=="google" then
        logVerbose("[IAP Badger] Running on Android (Google Play)")
        store=require("plugin.google.iap.billing.v2")
        store.init("google", storeTransactionCallback)
        storeAvailable = true
        --Init in Google IAP is asynchronous - record that the call has yet to complete
        storeInitialized = false
        initQueue = {}
        logVerbose("[IAP Badger] Using asynchronous Google IAP integration")
        logVerbose("[IAP Badger] Waiting for store to initialise, queuing future store functions.")
    elseif targetStore=="amazon" then
        logVerbose("[IAP Badger] Running on Android (Amazon)")
        --Switch to the amazon plug in
        store=require("plugin.amazon.iap")
        store.init(storeTransactionCallback)
        if (store.isActive) then storeAvailable=true end
        storeInitialized = true
    end

    --If running on the simulator, always run in debug mode
    debugMode=false
    if (targetStore=="simulator") then
        --Set debug mode
        debugMode=true
        --If a debug store to test was passed, use that
        if (options.debugStore~=nil) then debugStore=options.debugStore else debugStore="apple" end
        logVerbose ("[IAP Badger] Simulating target store: " .. debugStore)
        storeName = storeNames[targetStore]
        --If debug store is google, create a delay before completing initialisation to simulate asynchronous store.init on real device
        if (debugStore=="google") then
            storeInitialized = false
            initQueue = {}
            --Simulate device delay between starting init request and Google completing
            logVerbose ("[IAP Badger] Will simulate Google init transaction event in 750ms")
            timer.performWithDelay(750, function() storeTransactionCallback({name="init"}) end)
        end
    end

    --If debug mode has been set to true, always put in debug mode (even if on a device)
    if (options.debugMode==true) then debugMode=true end

    --Record store name
    if onSimulator==false then
        storeName = storeNames[targetStore]
    else
        storeName = storeNames[debugStore]
    end

    --If running on a device, and in debug mode, then make sure user knows
    if onSimulator==false and debugMode==true then
        native.showAlert("Warning", "Running IAP Badger in debug mode on device", {"Ok"})
    end

    initDone = true
    logVerbose("[IAP Badger] Leaving init")
end
public.init = init

local function setCancelledListener(listener)
    transactionCancelledListener=listener
end
public.setCancelledListener = setCancelledListener

local function setFailedListener(listener)
    transactionFailedListener = listener
end
public.setFailedListener = setFailedListener

--***************************************************************************************************************
--
-- Debug functions
--
-- Comment these out to prevent them any code related to them being included in the final build of your app
--
--***************************************************************************************************************


--Fake purchases for simulator
fakePurchase=function(productList)
    --Only execute in debug mode
    if (debugMode~=true) then return end

    --For every item in the product list
    for key, value in pairs(productList) do
        --Ask the user what they would like to do - this is put in a timer as Android doesn't like too many
        --native.showAlerts close together
        timer.performWithDelay(150,
            function()
                --Ask user what App Store response they would like to fake
                native.showAlert("Debug", "Purchase initiated for item: " .. value .. ".  What response would you like to give?",
                    { "Successful", "Cancelled", "Failed" },
                    function(event)
                        if (event.action=="clicked") then
                            --Create a fake event table
                            local fakeEvent={
                                transaction={
                                    productIdentifier=value,
                                    state=nil,
                                    errorType=nil,
                                    errorString=nil
                                }
                            }
                            --Get index of item clicked
                            local i = event.index
                            if (i==1) then
                                --Successful transactions
                                fakeEvent.transaction.state="purchased"
                            elseif (i==2) then
                                --Cancelled transactions
                                fakeEvent.transaction.state="cancelled"
                            elseif (i==3) then
                                --Failed transactions
                                fakeEvent.transaction.state="failed"
                                fakeEvent.transaction.errorType="Fake error"
                                fakeEvent.transaction.errorString="A debug error message describing nothing."
                            end  --end if i
                            --Fake callback
                            print("Purchasing " .. value)
                            storeTransactionCallback(fakeEvent)
                        end --endif event.action==clicked
                    end) --end native.showAlert

            end
        )
    end
end

--Restore listener
fakeRestoreListener=function(event)
    --Only execute in debug mode
    if (debugMode~=true) then return end

    --If an option was clicked...
    if (event.action=="clicked") then
        --Get a product list
        local productList = getProductList()
        --Get copy of item clicked
        local index = event.index
        --Timeout is easy to deal with
        if (index==1) then
            --Set up a timeout if the user specified a timeoutFunction to call
            if (fakeRestoreTimeoutFunction~=nil) then restorePurchasesTimer=timer.performWithDelay(fakeRestoreTimeoutTime,
                function()
                    --Kill the first restored item flag and fail callback pointer
                    firstRestoredItem=nil
                    restorePurchasesTimer=nil
                    actionType=nil
                    --Call the user defined timeout function
                    fakeRestoreTimeoutFunction()
                end)
            end
            return
        end

        --As is cancel
        if (index==3) then
            local fakeEvent={
                transaction={
                    productIdentifier="debugProductIdentifier",
                    state="cancelled",
                    errorType=nil,
                    errorString=nil
                }
            }
            storeTransactionCallback(fakeEvent)
            return
        end

        --And fail...
        if (index==2) then
            local fakeEvent={
                transaction={
                    productIdentifier="debugProductIdentifier",
                    state="failed",
                    errorType="Simulated error",
                    errorString="Fake error generated by debug."
                }
            }
            storeTransactionCallback(fakeEvent)
            return
        end

        --Restore all products...
        local productList = getProductList()
        --Iterate over the products
        for i=1, #productList do
            --Get the product
            local productID = getAppStoreID(productList[i])
            --If this product isn't consumable...
            local processItem=true;
            if (catalogue.products[productList[i]].productType~="non-consumable") then processItem=false end
            if (catalogue.products[productList[i]].allowRestore) then processItem=true end
            if (processItem) then
                --Create a fake event for this product
                local fakeEvent={
                    transaction={
                        productIdentifier=productID,
                        state="restored",
                        errorType=nil,
                        errorString=nil
                    }
                }
                --If on Google Play, change the state to purchased (no restored state exists on Google Play)
                if (targetStore=="google") then fakeEvent.transaction.state="purchased" end
                --Restore purchase (fake)
                print("Restoring " .. productID)
                storeTransactionCallback(fakeEvent)
            end
        end

    end
end

--Restores the given table of products.  These should be passed as item names in the catalogue
--rather than as app store ID's.
fakeRestoreProducts = function(productList)
    --If one item is passed as a string, convert it into a table
    if (type(productList)=="string") then
        productList = { productList }
    end

    --Restore all products...
    local productList = getProductList()
    --Iterate over the products
    for i=1, #productList do
        --Get the product
        local productID = productList[i]
        --Create a fake event for this product
        local fakeEvent={
            transaction={
                productIdentifier=productID,
                state="restored",
                errorType=nil,
                errorString=nil
            }
        }
        --If on Google Play, change the state to purchased (no restored state exists on Google Play)
        if (targetStore=="google") then fakeEvent.transaction.state="purchased" end
        --Restore purchase (fake)
        print("Restoring " .. productID)
        storeTransactionCallback(fakeEvent)
    end
end
public.fakeRestoreProducts=fakeRestoreProducts


--Fake restore
--Gives user a list of products to restore from
fakeRestore = function(timeout)
    --Only execute in debug mode
    if (debugMode~=true) then return end

    --Create option list
    local optionList={"Simulate time out", "Simulate fail", "Cancel", "Restore products"}

    --Ask user which product they would like to restore
    timer.performWithDelay(50, function() native.showAlert("Debug", "What restore callback would you like to simulate?", optionList, fakeRestoreListener) end)
end

--------------------------------------------------------------------------------
--
-- loadProducts
--

local loadProductsUserCallback=nil

--Prints out the contents of the loadProducts catalgoue to the console
local function printLoadProductsCatalogue()
    print("printLoadProductsCatalogue output:")
    print("----------------------------------")

    if loadProductsCatalogue==nil then
        print("nil")
        return
    end
    --Provide a useful feedback message if getLoadProductsCatalogue() has never been called.
    if loadProductsFinished==nil then
        print("getLoadProductsCatalogue() not yet called - loadProductsCatalogue is empty")
        return
    end

    if loadProductsFinished=="error" then
        print("Error occurred during loadProducts")
        return
    end

    if loadProductsFinished==false then
        print("Still waiting for product catalogue from relevant app store.")
        return
    end

    debugPrint(loadProductsCatalogue)
end
public.printLoadProductsCatalogue=printLoadProductsCatalogue

--Create a fake product event with information passed in the catalogue.  This function will be called from loadProducts when run in the
--simulator.  The user's callback function will be called after a brief delay.
local function fakeLoadProducts(callback)

    logVerbose("IAP Badger: entering fakeLoadProductsCallback")

    --Create a table containing faked data based on the product catalogue
    loadProductsCatalogue={}

    for key, value in pairs(catalogue.products) do

        --Create faked data
        local data={}
        --Use a title specified by the user (or a the product key in the catalogue if none is provided)
        if (value.simulatorTitle~=nil) then
            data.title=value.simulatorTitle
        else
            data.title = key
        end
        --Use the item description specified by the user (or a placeholder if none is provided)
        if (value.simulatorDescription~=nil) then
            data.description=value.simulatorDescription
        else
            data.description = "Product description goes here."
        end
        --Use the item price specified by the user (or a placehold if none is provided)
        if (value.simulatorPrice~=nil) then
            data.localizedPrice = value.simulatorPrice
        else
            data.localizedPrice = "$0.99"
        end
        --The product identifier is always the product name as specified for the current store
        data.productIdentifier = value.productNames[debugStore]
        --Type of purchase is always "inapp" (IAP badger doesn't currently support subscriptions)
        data.type="inapp"

        --Add data to callback table
        loadProductsCatalogue[key]=data

    end

    --Create fake callback event data
    local eventData={}
    eventData.products=loadProductsCatalogue

    --Set the load products flag to true
    loadProductsFinished=true

    --If no user callback then quit now
    if (loadProductsUserCallback==nil) then
        logVerbose("[IAP Badger] Leaving fakeLoadProductsCallback")
        return
    end

    --If a user specified callback function was specified, call it
    if (loadProductsUserCallback~=nil) then
        logVerbose("[IAP Badger] Calling user defined listener function")
        callback(event, loadProductsCatalogue)
        logVerbose("[IAP Badger] Returned from user defined listener function")
    end

    logVerbose("[IAP Badger] Leaving fakeLoadProductsCallback")

end

--Callback function
loadProductsCallback = function(event)

    if (verboseDebugOutput) then
        print("[IAP Badger] loadProductsCallback")
        print("[IAP Badger] Raw event data: ")
        debugPrint(event)
    end

    --If an error was reported (so the product catalogue couldn't be loaded), leave now
    if (event.isError) then
        loadProductsFinished = "error"
        logVerbose("[IAP Badger] Product catalogue couldn't be loaded due to error")
        logVerbose("[IAP Badger] Leaving loadProductsCallback")
        return
    end

    --Create an empty catalogue
    loadProductsCatalogue={}

    --Copy in all the valid products into the product catalogue
    for i=1, #event.products do
        --Grab a copy of the event data (only need to perform a shallow copy)
        local eventData={}
        for key, value in pairs(event.products[i]) do
            eventData[key]=value
        end
        --Convert the product identifier (app store specific) into a catalogue product name
        local catalogueKey=nil
        logVerbose("[IAP Badger] Checking product ID " .. eventData.productIdentifier .. " exists in product catalogue passed to iap.init")
        for key, value in pairs(catalogue.products) do
            if (value.productNames[targetStore]==eventData.productIdentifier) then
                catalogueKey = key
                break
            end
        end
        if (not catalogueKey) then
            print("[IAP Badger] Unable to find a catalogue product name for the product with identifier " .. eventData.productIdentifier)
        end
        --Store copy
        if (verboseDebugOutput) then
            print ("[IAP Badger] Product found: " .. eventData.productIdentifier .. " => " .. catalogueKey)
            print ("[IAP Badger] Storing product info as below")
            debugPrint(eventData)
        end

        loadProductsCatalogue[catalogueKey]=eventData
    end

    --Indicate load products is complete
    loadProductsFinished=true

    --If a user specified callback function was specified, call it
    if (loadProductsUserCallback~=nil) then
        logVerbose("[IAP Badger] Calling user defined listener function")
        loadProductsUserCallback(event, loadProductsCatalogue)
        logVerbose("[IAP Badger] Returned from user defined listener function")
    end

    logVerbose("[IAP Badger] Leaving loadProductsCallback")

end

--If possible, this function will download a product table from either Google Play, the App Store or Amazon and call the
--specified callback function when complete.  The function itself will return true, indicating that a request was made.
--If no product table is available, or the store cannot process the request, the function will return false.
--If running on the simulator, the user's callback function will be passed a fake array containing fake data based on the product
--catalogue specification.
--
--Assuming the function is successful, a table containing valid products will be placed in loadProductsCatalogue, which can be
--access by the getLoadProductsCatalogue function - so strictly speaking it is not always necessary to pass a callback and simply
--interrogate the loadProductsCatalogue instead.  The table will contain false if loadProducts failed, or nil if loadProducts has never
--been called.
--
--The loadProducts table will be in the form of:
--productName
--  {
--   product data
--  }
--productName
--  {
--   product data
--  }
--...
--
--
--callback (optional): the function to call after loadProducts is complete.  The original loadProducts callback event data from
--          Corona will be passed as paramater 1, the loadProductsCatalogue table as parameter 2.

loadProducts=function(callback)

    logVerbose("[IAP Badger] loadProducts")

    --On Google IAP, check that init has completed
    if ( (targetStore=="google") or ((targetStore=="simulator") and (debugStore=="google")) ) and (storeInitialized==false) then

        logVerbose("[IAP Badger] Google Play not yet initialised.  Queuing loadProducts.")

        --Queue up a load products
        item = {
            name="loadProducts",
            params={callback=nil}
        }
        if (callback) then item['params']['callback']=callback end
        initQueue[#initQueue+1]=item

        logVerbose("[IAP Badger] Leaving loadProducts")

        return
    end

    --Save the user callback function
    loadProductsUserCallback=callback

    --Reset load products flag
    loadProductsFinished=false

    --If running on the simulator, fake the product array
    if (targetStore=="simulator") or (debugMode) then
        --Run the fakeLoadProducts function on a timer to simulator delay contacting app store
        timer.performWithDelay(2500, function() fakeLoadProducts(callback) end)
        return true
    end

    --Return a nil value if products cannot be loaded from the real store
    if (store.canLoadProducts~=true) then
        logVerbose("[IAP Badger] store.canLoadProducts not set to true - loadProducts is not available")
        --Record that the loadProductsCatalgue failed
        loadProductsCatalogue=false
        --Return that this function failed
        logVerbose("[IAP Badger] Leaving loadProducts")
        return false
    end

    --Generate a list of products and subscriptions
    local listOfProducts={}
    local listOfSubscriptions={}
    for key, thisProduct in pairs(catalogue.products) do
        if thisProduct.productNames[targetStore] ~= nil then
            logVerbose("[IAP Badger] Preparing loadProducts for product ID " .. thisProduct.productNames[targetStore])
            if targetStore == "google" and getIsSubscription(key) then
                listOfSubscriptions[#listOfSubscriptions+1]=thisProduct.productNames[targetStore]
            else
                listOfProducts[#listOfProducts+1]=thisProduct.productNames[targetStore]
            end
        else
            logVerbose("[IAP Badger] Product " .. key .. " does not exist for " .. targetStore .. " store, not adding")
        end
    end

    --Load products and subscriptions
    logVerbose("[IAP Badger] Calling loadProducts")
    if targetStore == "google" and #listOfSubscriptions > 0 then
        store.loadProducts(listOfProducts, listOfSubscriptions, loadProductsCallback)
    else
        store.loadProducts(listOfProducts, loadProductsCallback)
    end

    logVerbose("[IAP Badger] Leaving loadProducts")

end
public.loadProducts = loadProducts


--Returns version number for library
local function getVersion()
    return version;
end
public.getVersion=getVersion

return public
