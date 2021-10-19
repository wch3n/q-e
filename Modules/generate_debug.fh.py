import sys
dtype=['complex','real','integer']
kind=['4','8']
mold=[0,1,2,3,4,5,6,7]


molds={}
for r in mold:
    m='('
    for i in range(0,r-1):
       m+=':,'
    m+=':)'
    if r==0: m=''
    molds[r]=m


proc=f'''
!WARNING: THIS FILE IS AUTOMATICALLY GENERATED BY {sys.argv[0]}
interface checkpoint
'''
subs=f'''!WARNING: THIS FILE IS AUTOMATICALLY GENERATED BY {sys.argv[0]}
'''

for t in dtype:
    for k in kind:
        for r in mold:
            array = False if r==0 else True
            sum_='sum' if array else ''
            maxval_='maxval' if array else ""
            proc+=f'''module procedure checkpoint_{t}_{k}_{r}
'''
            subs+=f'''
subroutine checkpoint_{t}_{k}_{r}( arr, file, line)
{t}(kind={k}), intent(in) :: arr{molds[r]}
character(len=64) :: fname
character(*) file
integer line
integer :: iun,reclen,i,j
{t}(kind={k}), allocatable :: arr_{molds[r]}
CHARACTER(LEN=6), EXTERNAL :: int_to_char
INTEGER, EXTERNAL :: find_free_unit
if ( .not. checkpoint_debug_active) then
    return
end if

counter = counter + 1
fname = trim(fname_prefix)// int_to_char(counter)
iun = find_free_unit()
inquire(iolength=reclen) arr
WRITE(*,*) msg_pref, file,':', line
if (testing) then
    WRITE(*,*) msg_pref,'reading {t}(kind={k}){molds[r]}', shape(arr), reclen, ' from file '//trim(fname)
    open (iun, file=trim(fname),form='UNFORMATTED',access='DIRECT',recl=reclen,action='read')
    allocate(arr_, mold=arr)
    read (iun, rec=1) arr_
    close(iun)
    write(*,*) msg_pref,'sum of absolute value of difference = ',{sum_}(abs(arr_-arr))
    write(*,*) msg_pref,'max of absolute value of difference = ',{maxval_}(abs(arr_-arr))
    write(*,*) msg_pref,'sum of absolute value of computed array = ',{sum_}(abs(arr))
    deallocate(arr_)
else ! write the file
    WRITE(*,*) msg_pref,'writing {t}(kind={k}){molds[r]}', shape(arr), reclen, ' on file '//trim(fname)
    open (iun, file=trim(fname),form='UNFORMATTED',access='DIRECT',recl=reclen,action='write')
    write (iun, rec=1) arr
    close(iun)
end if
end subroutine
'''
proc+='''end interface
'''

with open('debug_proc.fh','w') as o:
    o.write(proc)
with open('debug_sub.fh','w') as o:
    o.write(subs)

