--USE [LIVE_INTEGRA]
--GO
/****** Object:  StoredProcedure [dbo].[SPU_RETENTION_PEER2]    Script Date: 10/15/2013 16:10:14 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[SPU_RETENTION_PEER2]

AS
SET NOCOUNT ON;
declare @enddate datetime,@startdate datetime,@ErrorVar int

set @enddate = getdate() 
set @startdate = dateadd(d,-7,DATEADD(MONTH, DATEDIFF(MONTH, 0, @enddate), 0))


;WITH DateRanges AS 
(SELECT @startdate AS 'DateValue' ,case when datepart(dw,@startdate) in (2,3,4,5,6) then 1 else 0 end 'dw',case when datepart(dw,@startdate) in (2,3,4,5,6) then 1 end  'dw2'
UNION ALL
SELECT DATEADD(DAY, 1, DateValue), dw,case when datepart(dw,DateValue) in (1,2,3,4,5) then dw+1   end 'dw2' FROM DateRanges  WHERE DATEADD(DAY, 1, DateValue) < @enddate ) 
select d.id,d.row,d.datevalue 
into #dates
from (
SELECT row_number() over (partition by dw order by dw) id,row_number() over (partition by dw,month(datevalue) order by dw) row, * FROM DateRanges where dw2 is not null ) d 
--drop table #dates
--select * from #dates
declare @lastworkday datetime,@monfirstworkday datetime
--previous working day 00:00 time !!this gets around weekends

--first working day of month
set @monfirstworkday = 
					(select d.datevalue from
					#dates d
					where 
					month(d.datevalue) = month(@enddate) and
					d.row = 1)


if @monfirstworkday = cast(convert(varchar(10),@enddate,120) as datetime)

set @lastworkday = (select d.datevalue from
					#dates d
					where month(d.datevalue) <> month(@enddate) and
					row in (
					select max(d.row) from #dates d 
where month(d.datevalue) <> month(getdate())))
else
set @lastworkday = (select d.datevalue from
					#dates  d
					where month(d.datevalue) = month(@enddate) and
					row in (
					select max(d.row)-1 from #dates d 
					where month(d.datevalue) = month(@enddate)))

--select @lastworkday,@monfirstworkday,@enddate,@startdate

--select list of Retention users !!users & lookup must all be valid
select u.user_id,u.individual_profile,ul.valid_from,ul.valid_to 
into #u
from
users u 
join lookup ul on ul.lookup_short_desc = u.logname
join lookup_type ult on ult.lookup_type_ref = ul.lookup_type_ref
where ult.lookup_type_code = 'REBR' and
u.active = 'Y'
and ul.valid_from <= getdate()
and (ul.valid_to >= getdate() or ul.valid_to is null)
--DROP TABLE #U

CREATE INDEX U1
ON #u(user_id); 

CREATE INDEX U2
ON #u(individual_profile); 
	

--drop table #peer_out
create table #peer_out
([IND_PEER_REF] [int],
	[PEER_REF] [int] ,
	[PEER_TYPE] [int],
	[STATUS] [int] ,
	[VALID_FROM] [datetime] ,
	[VALID_TO] [datetime] ,
	[COMMENTS] [text] ,
	[CREATE_TIMESTAMP] [datetime] ,
	[CREATED_BY] [varchar](254),
	[UPDATE_TIMESTAMP] [datetime],
	[UPDATED_BY] [varchar](254) ,
	[IND_REF] [int] ,
	[Tracking_Code_Ref] [int],
	[reason] varchar(max) )

create table #peer_in
([IND_PEER_REF] [int],
	[PEER_REF] [int] ,
	[PEER_TYPE] [int],
	[STATUS] [int] ,
	[VALID_FROM] [datetime] ,
	[VALID_TO] [datetime] ,
	[COMMENTS] [text] ,
	[CREATE_TIMESTAMP] [datetime] ,
	[CREATED_BY] [varchar](254),
	[UPDATE_TIMESTAMP] [datetime],
	[UPDATED_BY] [varchar](254) ,
	[IND_REF] [int] ,
	[Tracking_Code_Ref] [int],
	[reason] varchar(max) )


 
/*----------------------------------------*/
/*CANCEL OUTWARD MEMBERS. RETENTION CALLS & PEERS*/



create table #can
(
--activity_ref int,
individual_ref int,
reason varchar(20),
result varchar(254)
)

--all  members who leave the previous day 
insert into #can
select 
i.individual_ref,'stat' 'reason', mem_stat.lookup_short_desc 'result'

from
	individual i
	join member m on m.individual_ref = i.individual_ref
--	join users u on u.user_id = al.assigned_user
	join update_history h on h.table_key = m.member_ref and  upper(h.column_altered) = 'MEMBER_STATUS'
	join lookup mem_stat on mem_stat.lookup_ref = h.lookup_key
	join lookup ind_type on ind_type.lookup_ref = i.type
where 
	ind_type.lookup_code = 'MEM'	
	and mem_stat.lookup_code in ('DUP','EXP','SUS','WIT','DCSD','LAP','RES')
	and h.date_effective >= @lastworkday
	and h.date_effective < @enddate


--all  grade change to divisional previous day
insert into #can
select 
i.individual_ref,'grad' 'reason',mg.description 'result'

from
	individual i 
	join member m on m.individual_ref = i.individual_ref
	join update_history h on h.table_key = m.member_ref and  upper(h.column_altered) = 'MEMBER_GRADE'--select * from update_history h where upper(h.column_altered) = 'MEMBER_GRADE'
	join membership_grade mg on mg.member_grade_ref = h.lookup_key
	join lookup ind_type on ind_type.lookup_ref = i.type
--	left outer join users u on u.user_id = al.assigned_user

where 
	ind_type.lookup_code = 'MEM'
	and mg.description not in ('UK','EU','Overseas','Jersey','Guernsey')
	and h.date_effective >= @lastworkday
	and h.date_effective < @enddate

--all exempt class change the previous day
insert into #can
select 
i.individual_ref,'class' 'reason',lkp_class.lookup_full_desc 'result'

from
	individual i 
	join member m on m.individual_ref = i.individual_ref
	join update_history h on h.table_key = m.member_ref and  upper(h.column_altered) = 'MEMBER_CLASS'--select * from update_history h where upper(h.column_altered) = 'MEMBER_CLASS'
	join lookup lkp_class on lkp_class.lookup_ref = h.lookup_key
	join lookup ind_type on ind_type.lookup_ref = i.type
--	left outer join users u on u.user_id = al.assigned_user

where 
	ind_type.lookup_code = 'MEM'
	and lkp_class.lookup_code in ('OLC','STU')
	and h.date_effective >= @lastworkday
	and h.date_effective < @enddate


-- change all pending calls to incomplete
update activity_log
set activity_status = (select l.lookup_ref from lookup l join lookup_type lt on lt.lookup_type_ref = l.lookup_type_ref where lookup_code = 'INC' and lt.lookup_type_code = 'ACTS'),
updated_by = 'Administrator',
update_timestamp = @enddate
 
from
	activity_log al
	join individual_log il on al.activity_ref = il.activity_ref
	join #can on il.individual_ref = #can.individual_ref
	join lookup lkp_stat on al.activity_status = lkp_stat.lookup_ref
	join lookup lkp_cat on lkp_cat.lookup_ref = al.category

where
	lkp_stat.lookup_full_desc = 'Pending'
	and lkp_cat.lookup_code in ('RET','MSL')
	and #can.reason <> 'stat'


update activity_log
set activity_status = (select l.lookup_ref from lookup l join lookup_type lt on lt.lookup_type_ref = l.lookup_type_ref where lookup_code = 'INC' and lt.lookup_type_code = 'ACTS'),
updated_by = 'Administrator',
update_timestamp = @enddate
 
from
	activity_log al
	join individual_log il on al.activity_ref = il.activity_ref
	join #can on il.individual_ref = #can.individual_ref
	join lookup lkp_stat on al.activity_status = lkp_stat.lookup_ref
	join lookup lkp_cat on lkp_cat.lookup_ref = al.category

where
	lkp_stat.lookup_full_desc = 'Pending'
	and lkp_cat.lookup_code in ('RET')
	and #can.reason = 'stat'


--end date MRT peer for all who have had calls cancelled


update ind_peer
set valid_to = @lastworkday,
status = (select l.lookup_ref from lookup l join lookup_type lt on lt.lookup_type_ref = l.lookup_type_ref where l.lookup_code = 'INACT' and lt.lookup_type_code = 'IPEERS'),
updated_by = 'Administrator',
update_timestamp = @enddate
--output inserted.* into #peer_in
output deleted.*,'Retention Peer Invalidated - ' +case when #can.reason = 'stat' then 'No longer active' when #can.reason = 'grad' then 'Changed to '+#can.result when #can.reason = 'class' then 'Change to '+#can.result end 'reason' into #peer_out --peer change

--select * 
from 
	ind_peer p
	join #can on #can.individual_ref = p.ind_ref  
	join lookup l on l.lookup_ref = p.peer_type
	join lookup  l_stat on l_stat.lookup_ref = p.status
	join lookup_type lt on lt.lookup_type_ref = l_stat.lookup_type_ref 
where 
	l.lookup_code in ('MRT') and
	l_stat.lookup_code = 'ACT' and 
	lt.lookup_type_code = 'IPEERS' and
--	and p.valid_from < @lastworkday and 
	(p.valid_to is null or p.valid_to >= @lastworkday)



update ind_peer
set valid_to = @lastworkday,
status = (select l.lookup_ref from lookup l join lookup_type lt on lt.lookup_type_ref = l.lookup_type_ref where l.lookup_code = 'INACT' and lt.lookup_type_code = 'IPEERS'),
updated_by = 'Administrator',
update_timestamp = @enddate

--select * 
from 
	ind_peer p
	join #can on #can.individual_ref = p.peer_ref  
	join lookup l on l.lookup_ref = p.peer_type
	join lookup  l_stat on l_stat.lookup_ref = p.status
	join lookup_type lt on lt.lookup_type_ref = l_stat.lookup_type_ref 

where 
	l.lookup_code in ('MRF') and
	l_stat.lookup_code = 'ACT' and 
	lt.lookup_type_code = 'IPEERS' and
--	and p.valid_from < @lastworkday and 
	(p.valid_to is null or p.valid_to >= @lastworkday)



/*------------------------*/

/*REACTIVATE INWARD MEMBERS. PEERS*/


CREATE TABLE #ACTM
(INDIVIDUAL_REF INT,
PEER_REF INT)
--select all who have become active previous day. include peer where exists
INSERT into #actm
select i.individual_ref,p.peer_ref
--,m.membership_no,h.*

from
	individual i 
	join member m on m.individual_ref = i.individual_ref
	join lookup lkp_class on lkp_class.lookup_ref = m.member_class
	join membership_grade mg on mg.member_grade_ref = m.member_grade
	join lookup ind_type on ind_type.lookup_ref = i.type
	join update_history h on h.table_key = m.member_ref and  upper(h.column_altered) = 'MEMBER_STATUS'
	join lookup mem_stat on mem_stat.lookup_ref = h.lookup_key
	left outer join (select p.ind_ref ,p.peer_ref
						from ind_peer p
						join lookup l on l.lookup_ref = p.peer_type and l.lookup_code in ('MRT')) p on p.ind_ref = i.individual_ref 
where 
	ind_type.lookup_code = 'MEM'
	and mem_stat.lookup_code = 'ACT'
	and mg.description in ('UK','EU','Overseas','Jersey','Guernsey')
	and lkp_class.lookup_code not in ('OLC','STU')
	and h.date_effective >= @lastworkday
	and h.date_effective < @enddate


--all who changed from divisional
insert into #actm
select i.individual_ref,p.peer_ref
--,m.membership_no,h.*

from
	individual i 
	join member m on m.individual_ref = i.individual_ref
	join lookup lkp_class on lkp_class.lookup_ref = m.member_class
	join lookup ind_type on ind_type.lookup_ref = i.type
	join update_history h on h.table_key = m.member_ref and  upper(h.column_altered) = 'MEMBER_GRADE'
	join lookup mem_stat on mem_stat.lookup_ref = m.member_status
	join membership_grade mg on mg.member_grade_ref = h.lookup_key
	left outer join (select p.ind_ref ,p.peer_ref
						from ind_peer p
						join lookup l on l.lookup_ref = p.peer_type and l.lookup_code in ('MRT')) p on p.ind_ref = i.individual_ref 
where 
	ind_type.lookup_code = 'MEM'
	and mem_stat.lookup_code = 'ACT'
	and mg.description in ('UK','EU','Overseas','Jersey','Guernsey')
	and lkp_class.lookup_code not in ('OLC','STU')
	and h.date_effective >= @lastworkday
	and h.date_effective < @enddate


--update existing retention peer where they are a current retention user
update ind_peer 
set valid_to = null,
status = (select l.lookup_ref from lookup  l join lookup_type lt on lt.lookup_type_ref = l.lookup_type_ref where l.lookup_code = 'ACT' and lt.lookup_type_code = 'IPEERS'),
updated_by = 'Administrator',
update_timestamp = getdate()
output deleted.*,'Retention Peer reactivated' 'reason' into #peer_out --peer change
--select *
from 
	ind_peer p
	join #actm m on p.peer_ref  = m.peer_ref and p.ind_ref = m.individual_ref
	join lookup  l_stat on l_stat.lookup_ref = p.status
	join lookup_type lt on lt.lookup_type_ref = l_stat.lookup_type_ref 
	join lookup l on l.lookup_ref = p.peer_type
	join #u u on u.individual_profile = p.peer_ref
where
	l.lookup_code in ('MRT') and 
--	l_stat.lookup_code = 'INACT' and 
	lt.lookup_type_code = 'IPEERS' and
	(p.valid_to is not null or 
	p.status not in  (select l.lookup_ref from lookup l join lookup_type lt on lt.lookup_type_ref = l.lookup_type_ref  where l.lookup_code = 'ACT' and lt.lookup_type_code = 'IPEERS'))
--select * from #actm

update ind_peer 
set valid_to = null,
status = (select l.lookup_ref from lookup l join lookup_type lt on lt.lookup_type_ref = l.lookup_type_ref where l.lookup_code = 'ACT' and lt.lookup_type_code = 'IPEERS'),
updated_by = 'Administrator',
update_timestamp = getdate()
--select *
from  
	ind_peer p
	join #actm m on p.peer_ref  = m.individual_ref and p.ind_ref = m.peer_ref
	join lookup l on l.lookup_ref = p.peer_type
	join #u u on u.individual_profile = p.ind_ref
	join lookup  l_stat on l_stat.lookup_ref = p.status
	join lookup_type lt on lt.lookup_type_ref = l_stat.lookup_type_ref 

where
	l.lookup_code in ('MRF') and
--	l_stat.lookup_code = 'INACT' and 
	lt.lookup_type_code = 'IPEERS' and
	(p.valid_to is not null or 
	p.status not in  (select l.lookup_ref from lookup l join lookup_type lt on lt.lookup_type_ref = l.lookup_type_ref where l.lookup_code = 'ACT' and lt.lookup_type_code = 'IPEERS'))
--and u.peer_ref is not null


--!!NEW PEERS NEED TO BE ASSIGNED FOR ALL OTHERS!!
--old invalid retention dev peers will still me sitting on records and will be removed later

/*------------------------*/


/*CURRENT PEER CHECK*/
create table #pc
(row int,
[IND_PEER_REF] [int] ,
	[PEER_REF] [int] NULL,
	[PEER_TYPE] [int] NULL,
	[STATUS] [int] NULL,
	[VALID_FROM] [datetime] NULL,
	[VALID_TO] [datetime] NULL,
	[COMMENTS] [text] ,
	[CREATE_TIMESTAMP] [datetime] ,
	[CREATED_BY] [varchar](254) ,
	[UPDATE_TIMESTAMP] [datetime] ,
	[UPDATED_BY] [varchar](254) ,
	[IND_REF] [int] NULL,
	[Tracking_Code_Ref] [int]
)

insert into #pc
select row_number() over (partition by p.ind_ref order by isnull(p.valid_to,'3001-01-01') desc) row,
p.* 
--into #pc
from 
	ind_peer p
	join individual i on p.ind_ref = i.individual_ref
	join member m on m.individual_ref = i.individual_ref
	join lookup mem_stat on mem_stat.lookup_ref = m.member_status
	join lookup ind_type on ind_type.lookup_ref = i.type
	join membership_grade mg on mg.member_grade_ref = m.member_grade
	join lookup l on l.lookup_ref = p.peer_type
	join #u u on p.peer_ref  = u.individual_profile 
where 
	l.lookup_code in ('MRT') and
	p.valid_from <= getdate() and 
	(p.valid_to is null or p.valid_to >= cast(convert(varchar(10),getdate(),120) as datetime)) and
	ind_type.lookup_code = 'MEM' and 
	mem_stat.lookup_code = 'ACT'

CREATE INDEX X1
ON #pc(ind_peer_ref);

CREATE INDEX X2
ON #pc(ind_ref);



/*ASSIGN NEW PEERS*/


select i.individual_ref,u.individual_profile 
into #n
from
	individual i 
	join member m on m.individual_ref = i.individual_ref
	join lookup mem_stat on mem_stat.lookup_ref = m.member_status
	join lookup lkp_class on lkp_class.lookup_ref = m.member_class
	join lookup ind_type on ind_type.lookup_ref = i.type
	join membership_grade mg on mg.member_grade_ref = m.member_grade
	left outer join #pc p on p.ind_ref = i.individual_ref
	left outer join (	select --most recent pending call
							row_number() over (partition by il.individual_ref order by il.individual_ref,al.activity_date desc) row,
							il.individual_ref,al.assigned_user --u.user_id,u.individual_profile
						from activity_log al
							join individual_log il on al.activity_ref = il.activity_ref
--							join #u u on al.assigned_user = u.user_id and user_id <> 53
							join lookup lkp_stat on al.activity_status = lkp_stat.lookup_ref
										and lkp_stat.lookup_full_desc = 'Pending'
							join lookup lkp_type on al.activity_type = lkp_type.lookup_ref
										 and lkp_type.lookup_full_desc like 'Telephone Call Outgoing'
						where 
							al.activity_date >= @lastworkday  
					) c on c.individual_ref = i.individual_ref and c.row = 1
left outer join #u u on c.assigned_user = u.user_id 
where 
	ind_type.lookup_code = 'MEM'
	and mem_stat.lookup_code = 'ACT'
	and p.ind_ref is null
	and mg.description in ('UK','EU','Overseas','Jersey','Guernsey')
	and lkp_class.lookup_code not in ('OLC','STU')
order by
	i.individual_ref


--assign random user to new members or members with no valid dev
select distinct user_id,individual_ref
into #new
from
	(SELECT  
		row_number() over (partition by #n.individual_ref order by REVERSE(CONVERT(varchar(100), v_generate_rowid.rowid))) row,
		users.[user_id],#n.*
	FROM users
		INNER JOIN lookup_type ON lookup_type.lookup_type_code = 'REBR'
		INNER JOIN lookup REBR ON REBR.lookup_type_ref = lookup_type.lookup_type_ref
						AND users.logname = REBR.lookup_short_desc
		CROSS JOIN v_generate_rowid
		cross join #n where #n.individual_profile is null
	
		) u 
where 
	u.row = 1


insert into #new
select #u.user_id,#n.individual_ref
from
	#u
	join #n on #n.individual_profile = #u.individual_profile
where 
	#n.individual_profile is not null


--insert new peers
insert into ind_peer (peer_ref,peer_type,status,valid_from,create_timestamp,created_by,ind_ref)

select
	#new.individual_ref,
	(select l.lookup_ref from lookup l join lookup_type lt on lt.lookup_type_ref = l.lookup_type_ref where l.lookup_code in ('MRF') and lt.lookup_type_code = 'IPEERT'),
	 (select l.lookup_ref from lookup l join lookup_type lt on lt.lookup_type_ref = l.lookup_type_ref  where l.lookup_code = 'ACT' and lt.lookup_type_code = 'IPEERS'),
	getdate(),
	getdate(),
	'Administrator',
	u.individual_profile
from 
	#new
	join users u on u.user_id = #new.user_id



insert into ind_peer (peer_ref,peer_type,status,valid_from,create_timestamp,created_by,ind_ref)
output inserted.*,'New Retention Peer' 'reason' into #peer_in --peer change

select
	u.individual_profile,
	(select l.lookup_ref from lookup l join lookup_type lt on lt.lookup_type_ref = l.lookup_type_ref where l.lookup_code in ('MRT') and lt.lookup_type_code = 'IPEERT'),
	(select l.lookup_ref from lookup l join lookup_type lt on lt.lookup_type_ref = l.lookup_type_ref  where l.lookup_code = 'ACT' and lt.lookup_type_code = 'IPEERS'),
	getdate(),
	getdate(),
	'Administrator',
	#new.individual_ref
from 
	#new
	join users u on u.user_id = #new.user_id
	


/*REMOVE OLDER NON-CURRENT MRT & MRF PEERS WHERE MORE THAN ONE EXISTS*/

--select oldest active peer where duplicates exist
select
*
into #xp
from
(
select row_number() over (partition by p.ind_ref order by lk_pstat.lookup_code,p.ind_peer_ref desc /*isnull(p.valid_to,'3001-01-01') desc*/ ) row,
p.* 

from 
	ind_peer p
	join individual i on p.ind_ref = i.individual_ref
	join member m on m.individual_ref = i.individual_ref
	join lookup mem_stat on mem_stat.lookup_ref = m.member_status
	join lookup ind_type on ind_type.lookup_ref = i.type
	join lookup l on l.lookup_ref = p.peer_type
	join lookup lk_pstat on lk_pstat.lookup_ref = p.status
where 
	l.lookup_code in ('MRT') and
	ind_type.lookup_code = 'MEM' and 
	mem_stat.lookup_code = 'ACT' 

	) a where row > 1

--delete additional peers selected
delete ind_peer
output deleted.*,'Retention Peer superseded' 'reason' into #peer_out --peer change

--select * 
from
	ind_peer p
	join #xp x on x.ind_peer_ref = p.ind_peer_ref
	join lookup l on l.lookup_ref = p.peer_type
where 
	lookup_code in ('MRT')


--select and delete reflex (this could probably be done better)
select
	*
into #xp2
from
	(
	select row_number() over (partition by p.peer_ref order by lk_pstat.lookup_code,p.ind_peer_ref desc /*isnull(p.valid_to,'3001-01-01') desc*/  ) row,
	p.* 
	--into #pc
	from 
		ind_peer p
	join lookup l on l.lookup_ref = p.peer_type
	join lookup lk_pstat on lk_pstat.lookup_ref = p.status
	join #peer_out po on po.ind_ref = p.peer_ref and po.reason = 'Retention Peer superseded'
	where 
		l.lookup_code in ('MRF') --and p.peer_ref = 1779100
	) a where row > 1



delete ind_peer
--select * 
from
	ind_peer p
	join #xp2 x on x.ind_peer_ref =  p.ind_peer_ref
	join lookup l on l.lookup_ref = p.peer_type
where 
	lookup_code in ('MRF')


/*CHECK FOR PEER CHANGES*/

--select all active peers
select  
	MDO.*
	
into #peerchange
from
	ind_peer MDO  

	JOIN	individual i	ON MDO.ind_ref = i.individual_ref 
	JOIN	member m	ON i.individual_ref = m.individual_ref 
	JOIN	individual MDO_ind	ON MDO.peer_ref = MDO_ind.individual_ref 
	join	member MDO_mem on MDO_mem.individual_ref = MDO_ind.individual_ref
	left outer join lookup l on l.lookup_ref = MDO.peer_type 
	left outer join users u on u.individual_profile = MDO.peer_ref
	join lookup  l_stat on l_stat.lookup_ref = MDO.status

where --
	l.lookup_code = 'MRT' and 
	l_stat.lookup_code = 'ACT' and 
	MDO.valid_from < @enddate and 
	(MDO.valid_to is null or MDO.valid_to >= @lastworkday)

--identify changed peers
insert into #peer_out
select
ipl.*,
'Peer Changed' 'reason'
from
iod_peer_last ipl
--join ind_peer p on p.ind_peer_ref = ipm.ind_peer_ref
join #peerchange cp on cp.ind_peer_ref = ipl.ind_peer_ref
where ipl.peer_ref <> cp.peer_ref


--previous day peer snapshot replaced
truncate table iod_peer_last 

--insert new peer selection
insert into iod_peer_last
select * from #peerchange

--select * from iod_peer_last



/*---------------------------------------------------*/
/*ADD MEMO TO ADVISE OF PEER CHANGES*/


create table #pm
( individual_ref int,
activity_ref int)

insert into activity_log --select * from activity_log
		(individual_ref,
		activity_type,
		category,
		comments,
		activity_date,
		activity_user,
		completed,
		create_timestamp,
		created_by,
		activity_status)
output inserted.individual_ref, inserted.activity_ref into #pm
select
	po.ind_ref,
	(select l.lookup_ref from lookup l join lookup_type lt on lt.lookup_type_ref = l.lookup_type_ref where l.lookup_code = 'NMO' and lt.lookup_type_code = 'ACTT'),
	(select l.lookup_ref from lookup l join lookup_type lt on lt.lookup_type_ref = l.lookup_type_ref where lookup_code = 'GEN' and lt.lookup_type_code = 'ACTCAT'),
	'PEER UPDATE - '+ UPPER(PO.REASON)+' - '+U.FULLNAME+' - #'+cast(u.user_id as varchar(10)) ,
	@enddate,
	1, 
	--MDO.user_id,
	'Y',
	getdate(),
	'Administrator',
	(select lookup_ref from lookup where lookup_full_desc in ('Completed') and lookup_type_ref = 59)
--select *
from 
#peer_out po
JOIN users u on u.individual_profile = po.peer_ref


insert into activity_log --select * from activity_log
		(individual_ref,
		activity_type,
		category,
		comments,
		activity_date,
		activity_user,
		completed,
		create_timestamp,
		created_by,
		activity_status)
output inserted.individual_ref, inserted.activity_ref into #pm
select
	pi.ind_ref,
	(select l.lookup_ref from lookup l join lookup_type lt on lt.lookup_type_ref = l.lookup_type_ref where l.lookup_code = 'NMO' and lt.lookup_type_code = 'ACTT'),
	(select l.lookup_ref from lookup l join lookup_type lt on lt.lookup_type_ref = l.lookup_type_ref where lookup_code = 'GEN' and lt.lookup_type_code = 'ACTCAT'),
	'PEER UPDATE - '+ UPPER(PI.REASON)+' - '+U.FULLNAME+' - #'+cast(u.user_id as varchar(10)),
	@enddate,
	1, 
	--MDO.user_id,
	'Y',
	getdate(),
	'Administrator',
	(select l.lookup_ref  from lookup l join lookup_type lt on lt.lookup_type_ref = l.lookup_type_ref where l.lookup_full_desc in ('Completed') and lt.lookup_type_code = 'ACTS')
--select *
from 
#peer_in pi
JOIN users u on u.individual_profile = pi.peer_ref



insert into individual_log 
	(individual_ref,
	activity_ref,
	create_timestamp,
	created_by)
select
	#pm.individual_ref,
	#pm.activity_ref,
	getdate(),
	1
	
from
#pm 




/*----------------------------------------*/

/*RE-ASSIGN CALLS WHERE PEER HAS CHANGED*/


update activity_log

set 
assigned_user = c.user_id,
--action_date = getdate(),
updated_by = 'Administrator',
update_timestamp = @enddate
--select *
from 
	activity_log al
	join individual_log il on al.activity_ref = il.activity_ref
	join individual i on i.individual_ref = il.individual_ref --select * from individual
	join member m on m.individual_ref = i.individual_ref
	join lookup mem_stat on mem_stat.lookup_ref = m.member_status
	join lookup ind_type on ind_type.lookup_ref = i.type
	join lookup lkp_stat on al.activity_status = lkp_stat.lookup_ref
		and lkp_stat.lookup_full_desc = 'Pending'
	join lookup lkp_type on al.activity_type = lkp_type.lookup_ref
		 and lkp_type.lookup_full_desc like 'Telephone Call Outgoing'
	join users u on u.user_id = al.assigned_user --po.peer_ref
	join #peer_out po on po.ind_ref = i.individual_ref and u.individual_profile = po.peer_ref
	join lookup l on l.lookup_ref = po.peer_type
	left outer join (select p.* ,u2.user_id
						from
						ind_peer p 
	
							join users u2 on p.peer_ref = u2.individual_profile
							join lookup l on l.lookup_ref = p.peer_type

						where
							l.lookup_code in ('MRT') ) c on c.ind_ref = i.individual_ref 

where

	l.lookup_code in ('MRT')
	--and p.valid_from <= getdate() /*@lastworkday*/ and p.valid_to is null 
	and al.assigned_user <> c.user_id


/*INCOMPLETE OLD RETENTION CALLS ASSIGNED TO MEMDEV USERS OTHER THAN PEER */


update activity_log
set activity_status = (select l.lookup_ref from lookup l join lookup_type lt on lt.lookup_type_ref = l.lookup_type_ref where lookup_code = 'INC' and lt.lookup_type_code = 'ACTS'),
updated_by = 'Administrator',
update_timestamp = @enddate
--select *
from
	activity_log al
	join individual_log il on al.activity_ref = il.activity_ref
	join users u on isnull(al.assigned_user,al.activity_user) = u.user_id and u.grpname like 'MemDev%'	
	join lookup lkp_stat on al.activity_status = lkp_stat.lookup_ref
		and lkp_stat.lookup_full_desc = 'Pending'
	join lookup lkp_type on al.activity_type = lkp_type.lookup_ref
		and lkp_type.lookup_full_desc like 'Telephone Call Outgoing'
	join lookup lkp_cat on lkp_cat.lookup_ref = al.category
		and lkp_cat.lookup_code in ('RET','MSL')
	join #peerchange p1 on p1.ind_ref = il.individual_ref

		left outer join ( select p.peer_ref,p.ind_ref 
							from 
							ind_peer p 
							join lookup l on l.lookup_ref = p.peer_type
							where l.lookup_code in ('MRT') and
							p.valid_from <= getdate() and 
							(p.valid_to is null or p.valid_to >= getdate())) p on p.ind_ref = il.individual_ref

where 
	al.create_timestamp < cast(convert(varchar(10),getdate(),120) as datetime) and
	al.activity_date < cast(convert(varchar(10),getdate()-1,120) as datetime) and
	(p.peer_ref <> u.individual_profile or p.ind_ref is null or u.individual_profile is null)
