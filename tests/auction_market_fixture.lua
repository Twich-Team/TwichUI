-- Representative synthetic local observations, ingested by the real writer.
return function(c)
    local W=c.TwichUI.Workshop
    local now=20000*86400+43200
    c.time=function() return now end
    c.GetRealmName=function() return "Realm" end
    c.TwichUIWorkshopDB={v=2,markets={}}
    c.C_Item.GetItemInfo=function(id)
        if id==14 then return nil end
        return ({[10]="Elemental Earth",[11]="Silk Cloth",[12]="A Very Long Enchanted Sword of Historical Market Research"})[id] or "Item "..id,
            nil,id==12 and 3 or 1,nil,nil,id==12 and "Weapon" or "Trade Goods","Elemental",nil,nil,134572,40,id==12 and 2 or 7,nil,0
    end
    local key="Realm|Alliance"
    for day=19890,20000 do
        if day%5~=0 or day==20000 then
            local b=W.Prices.NewBatch()
            b:Add(10,20,20*(20000+(day%11)*100),true)
            b:Add(10,30,30*(23000+(day%11)*100),true)
            if day==19998 then b:Add(11,2,1000,true) end
            local items,n,_,_,dist=b:Items()
            assert(W.Prices.Commit(key,{realm="Realm",side="Alliance",at=day*86400+3600,
                complete=true,read=n,used=n,n=n,items=items,alg=W.Dist.ALG,dist=dist}))
        end
    end
    local m=W.Prices.Market(key)
    local b=W.Prices.NewBatch();b:Add(10,2,1800,true)
    local items,n,_,_,dist=b:Items()
    assert(W.Prices.Commit("Realm|Horde",{realm="Realm",side="Horde",at=now-1800,complete=false,
        partial=1,read=n,used=n,n=n,items=items,alg=W.Dist.ALG,dist=dist}))
    return W,m,now
end
