MODULE module_wtable

use module_parallel
use module_rootdepth

implicit none

real, parameter :: pi4=3.1415927 * 4.

CONTAINS
!     ******************************************************************

subroutine WTABLE(imax,jmax,is,ie,js,je,nzg,slz,dz,area,soiltxt,wtd,bottomflux,rech,qslat,fdepth,topo,landmask,deltat &
                 ,smoi,smoieq,smoiwtd,qsprings)

integer :: imax,jmax,is,ie,js,je,nzg,i,j,nsoil
real :: deltat,totwater,qspring,wgpmid,kfup,vt3dbdw,newwgp
real , dimension(nzg+1) :: slz
real , dimension(nzg) :: dz
real,dimension(is:ie,js:je):: area,fdepth,wtd,rech,bottomflux,qslat,topo &
                      ,smoiwtd,klat,qsprings,qlat,deeprech
real,dimension(nzg,is:ie,js:je):: smoi,smoieq
integer, dimension(2,is:ie,js:je)::soiltxt
integer, dimension(is:ie,js:je) :: landmask
integer :: reqsu,reqsd,reqru,reqrd


if(numtasks.gt.1)call SENDBORDERS(imax,js,je,wtd,reqsu,reqsd,reqru,reqrd)


!Calculate lateral flow
qlat=0.

do j=js,je
   do i=1,imax
       nsoil=soiltxt(1,i,j)
       klat(i,j)=slcons(nsoil)*klatfactor(nsoil)
   enddo
enddo


!make sure that the borders are received before calculating lateral flow
   if(pid.eq.1)then
       call  MPI_wait(reqru,status,ierr)
   elseif(pid.eq.numtasks-2)then
       call  MPI_wait(reqrd,status,ierr)
   elseif(pid.gt.1.and.pid.lt.numtasks-2)then
      call  MPI_wait(reqru,status,ierr)
      call  MPI_wait(reqrd,status,ierr)
   endif

call lateralflow(imax,jmax,is,ie,js,je,wtd,qlat,fdepth,topo,landmask,deltat,area,klat)

qslat=qslat+qlat*1.e3

!now calculate deep recharge
deeprech=0.

DO j=js+1,je-1
  DO i=1,imax
if(landmask(i,j).eq.1)then

   if(wtd(i,j).lt.slz(1)-dz(1))then

!calculate k for drainage
            nsoil=soiltxt(1,i,j)
            wgpmid = 0.5 * (smoiwtd(i,j) + slmsts(nsoil))
            kfup =  slcons(nsoil) &
               * (wgpmid / slmsts(nsoil)) ** (2. * slbs(nsoil) + 3.)

!now calculate moisture potential
            vt3dbdw = slpots(nsoil)  &
               * (slmsts(nsoil) / smoiwtd(i,j)) ** slbs(nsoil)

!and now flux (=recharge)
             deeprech(i,j) = deltat * kfup &
               * ( (slpots(nsoil)-vt3dbdw)/(slz(1)-wtd(i,j))  - 1. )

!now update smoiwtd

            newwgp=smoiwtd(i,j) + (deeprech(i,j) - bottomflux(i,j)) / (slz(1)-wtd(i,j))
            if(newwgp.lt.soilcp(nsoil))then
                    deeprech(i,j)=deeprech(i,j)+(soilcp(nsoil)-newwgp)*(slz(1)-wtd(i,j))
                    newwgp=soilcp(nsoil)
            endif
            if(newwgp.gt.slmsts(nsoil))then
                    deeprech(i,j)=deeprech(i,j)-(slmsts(nsoil)-newwgp)*(slz(1)-wtd(i,j))
                    newwgp=slmsts(nsoil)
            endif

            smoiwtd(i,j)=newwgp

            rech(i,j) = rech(i,j)  + deeprech(i,j)*1.e3

    endif

endif
  ENDDO
ENDDO


      bottomflux=0.



!before changing wtd make sure that the borders have been received

   if(pid.eq.1)then
       call  MPI_wait(reqsu,status,ierr)
   elseif(pid.eq.numtasks-2)then
       call  MPI_wait(reqsd,status,ierr)
   elseif(pid.gt.1.and.pid.lt.numtasks-2)then
      call  MPI_wait(reqsu,status,ierr)
      call  MPI_wait(reqsd,status,ierr)
   endif

!Now update water table and soil moisture

!write(6,*)'now to updatewtd'

DO j=js+1,je-1
  DO i=1,imax

if(landmask(i,j).eq.1)then

!Total groundwater balance in the cell
       totwater = qlat(i,j)  - deeprech(i,j)
if(qlat(i,j).ne.qlat(i,j))write(6,*)'gran problema!',wtd(i,j),qlat(i,j),i,j

       call updatewtd(nzg,slz,dz,wtd(i,j),qspring,totwater,smoi(1,i,j) &
                      ,smoieq(1,i,j),soiltxt(1,i,j),smoiwtd(i,j))

       qsprings(i,j) = qsprings(i,j) + qspring*1.e3


endif

  ENDDO
ENDDO



end subroutine wtable

!     ******************************************************************

subroutine LATERAL(imax,jmax,is,ie,js,je,nzg,soiltxt,wtd,qlat,fdepth,topo,landmask,deltat,area,lats,dxy,slz &
                  ,o18,smoi,qlato18,qlatinsum,qlatoutsum,qlatino18sum,qlatouto18sum)

integer :: imax,jmax,is,ie,js,je,nzg,i,j,nsoil,k,kwtd
real :: deltat,dxy
real,dimension(is:ie,js:je):: area,fdepth,wtd,qlat,topo,klat,lats
real,dimension(is:ie,js:je):: qlato18,o18wtd,qlatin,qlatout,qlatinsum,qlatoutsum,qlatino18,qlatouto18,qlatino18sum,qlatouto18sum
real, dimension(nzg+1) :: slz
integer, dimension(2,is:ie,js:je)::soiltxt
integer, dimension(is:ie,js:je) :: landmask
real, dimension(nzg,is:ie,js:je) :: o18,smoi,o18ratio

if(numtasks.gt.1)call SENDBORDERS4(is,ie,js,je,wtd)


!Calculate lateral flow
qlat=0.
qlato18=0.
qlatin=0.
qlatout=0.
qlatino18=0.
qlatouto18=0.

do j=max(js,1),min(je,jmax)
  do i=max(is,1),min(ie,imax)
       nsoil=soiltxt(1,i,j)
       klat(i,j)=slcons(nsoil)*klatfactor(nsoil)

       do k=1,nzg
       if(wtd(i,j).lt.slz(k))exit
       enddo
       kwtd=max(k-1,1)
       o18wtd(i,j)=o18(kwtd,i,j)/smoi(kwtd,i,j)
   enddo
enddo


if(numtasks.gt.1)call SENDBORDERS4(is,ie,js,je,o18wtd)


call lateralflow4(imax,jmax,is,ie,js,je,wtd,qlat,fdepth,topo,landmask,deltat,area,klat,lats,dxy,o18wtd,qlato18,qlatin,qlatout,qlatino18,qlatouto18)


              qlatinsum = qlatinsum + qlatin*1.e3
              qlatoutsum = qlatoutsum + qlatout*1.e3
              qlatino18sum = qlatino18sum + qlatino18*1.e3
              qlatouto18sum = qlatouto18sum + qlatouto18*1.e3
end subroutine lateral

!     ******************************************************************

subroutine UPDATEDEEPWTABLE(imax,jmax,js,je,nzg,slz,dz,soiltxt,wtd,bottomflux,rech &
               ,qslat,qlat,landmask,deltat,smoi,smoieq,smoiwtd,qsprings)

integer :: imax,jmax,js,je,nzg,i,j,nsoil
real :: deltat,totwater,qspring,wgpmid,kfup,vt3dbdw,newwgp
real , dimension(nzg+1) :: slz
real , dimension(nzg) :: dz
real,dimension(imax,js:je):: wtd,rech,bottomflux,qslat,qlat &
                      ,smoiwtd,qsprings,deeprech
real,dimension(nzg,imax,js:je):: smoi,smoieq
integer, dimension(2,imax,js:je)::soiltxt
integer, dimension(imax,js:je) :: landmask

!calculate deep recharge
deeprech=0.

DO j=js+1,je-1
  DO i=1,imax
if(landmask(i,j).eq.1)then

   if(wtd(i,j).lt.slz(1)-dz(1))then

!calculate k for drainage
            nsoil=soiltxt(1,i,j)
            wgpmid = 0.5 * (smoiwtd(i,j) + slmsts(nsoil))
            kfup =  slcons(nsoil) &
               * (wgpmid / slmsts(nsoil)) ** (2. * slbs(nsoil) + 3.)

!now calculate moisture potential
            vt3dbdw = slpots(nsoil)  &
               * (slmsts(nsoil) / smoiwtd(i,j)) ** slbs(nsoil)

!and now flux (=recharge)
             deeprech(i,j) = deltat * kfup &
               * ( (slpots(nsoil)-vt3dbdw)/(slz(1)-wtd(i,j))  - 1. )

!now update smoiwtd

            newwgp=smoiwtd(i,j) + (deeprech(i,j) - bottomflux(i,j)) / (slz(1)-wtd(i,j))
            if(newwgp.lt.soilcp(nsoil))then
                    deeprech(i,j)=deeprech(i,j)+(soilcp(nsoil)-newwgp)*(slz(1)-wtd(i,j))
                    newwgp=soilcp(nsoil)
            endif
            if(newwgp.gt.slmsts(nsoil))then
                    deeprech(i,j)=deeprech(i,j)-(slmsts(nsoil)-newwgp)*(slz(1)-wtd(i,j))
                    newwgp=slmsts(nsoil)
            endif

            smoiwtd(i,j)=newwgp

            rech(i,j) = rech(i,j)  + deeprech(i,j)*1.e3

    endif

endif
  ENDDO
ENDDO

      bottomflux=0.

DO j=js+1,je-1
  DO i=1,imax

if(landmask(i,j).eq.1)then

!Total groundwater balance in the cell
       totwater = qlat(i,j) -qslat(i,j) - deeprech(i,j)

       call updatewtd(nzg,slz,dz,wtd(i,j),qspring,totwater,smoi(1,i,j) &
                      ,smoieq(1,i,j),soiltxt(1,i,j),smoiwtd(i,j))

       qsprings(i,j) = qsprings(i,j) + qspring*1.e3

endif

  ENDDO
ENDDO

!qlat=qlat*1.e3

end subroutine updatedeepwtable

!     ******************************************************************

subroutine LATERALFLOW(imax,jmax,is,ie,js,je,wtd,qlat,fdepth,topo,landmask,deltat,area,klat)
implicit none
real :: deltat,fangle,q
integer :: imax,jmax,is,ie,js,je,i,j
integer, dimension(is:ie,js:je):: landmask
real,dimension(is:ie,js:je)::fdepth,wtd,qlat,topo,area,kcell,klat,head

fangle=sqrt(tan(pi4/32.))/(2.*sqrt(2.))


!gmmlateral flow calculation
!WHERE(fdepth.lt.1.e-6)
!  kcell=0.
!ELSEWHERE(wtd.lt.-1.5)
!   kcell=fdepth*klat*exp((wtd+1.5)/fdepth)
!ELSEWHERE
!   kcell=klat*(wtd+1.5+fdepth)
!END WHERE

do j=max(js,1),min(je,jmax)
  do i=max(is,1),min(ie,imax)
      if(fdepth(i,j).lt.1.e-6)then
          kcell(i,j)=0.
      elseif(wtd(i,j).lt.-1.5)then
          kcell(i,j)=fdepth(i,j)*klat(i,j)*exp((wtd(i,j)+1.5)/fdepth(i,j))
      else
          kcell(i,j)=klat(i,j)*(wtd(i,j)+1.5+fdepth(i,j))
      endif

      head(i,j) = topo(i,j) + wtd(i,j)
  enddo
enddo

!head=topo+wtd


do j=js+1,je-1       
  do i=is+1,ie-1      

IF(landmask(i,j).eq.1) then

q=0.

q  = q + (kcell(i-1,j+1)+kcell(i,j)) &
        * (head(i-1,j+1)-head(i,j))/sqrt(2.)

q  = q +  (kcell(i-1,j)+kcell(i,j)) &
        *  (head(i-1,j)-head(i,j))
                     
q  = q +  (kcell(i-1,j-1)+kcell(i,j)) &
        * (head(i-1,j-1)-head(i,j))/sqrt(2.)

q  = q +  (kcell(i,j+1)+kcell(i,j)) &
        * (head(i,j+1)-head(i,j))

q  = q +  (kcell(i,j-1)+kcell(i,j)) &
         * (head(i,j-1)-head(i,j))

q  = q +  (kcell(i+1,j+1)+kcell(i,j)) &
         * (head(i+1,j+1)-head(i,j))/sqrt(2.)

q  = q +  (kcell(i+1,j)+kcell(i,j)) &
         * (head(i+1,j)-head(i,j))

q  = q +  (kcell(i+1,j-1)+kcell(i,j)) &
         * (head(i+1,j-1)-head(i,j))/sqrt(2.)

qlat(i,j) = fangle* q * deltat / area(i,j)

ENDIF
   enddo
enddo


end subroutine lateralflow

!     ******************************************************************

subroutine LATERALFLOW4(imax,jmax,is,ie,js,je,wtd,qlat,fdepth,topo,landmask,deltat,area,klat,xlat,dxy,o18wtd,qlato18,qlatin,qlatout,qlatino18,qlatouto18)
implicit none
double precision,parameter :: d2r = 0.0174532925199
real :: deltat,fangle,q,dxy,qn,qs,qe,qw,qo18,qno18,qso18,qeo18,qwo18,qin,qout,qino18,qouto18
integer :: imax,jmax,is,ie,js,je,nzg,i,j
integer, dimension(is:ie,js:je):: landmask
real,dimension(is:ie,js:je)::fdepth,wtd,qlat,topo,area,kcell,klat,head,xlat,o18wtd,qlato18,qlatin,qlatout,qlatino18,qlatouto18


!gmmlateral flow calculation
!WHERE(fdepth.lt.1.e-6)
!  kcell=0.
!ELSEWHERE(wtd.lt.-1.5)
!   kcell=fdepth*klat*exp((wtd+1.5)/fdepth)
!ELSEWHERE
!   kcell=klat*(wtd+1.5+fdepth)
!END WHERE


do j=max(js,1),min(je,jmax)
  do i=max(is,1),min(ie,imax)
      if(fdepth(i,j).lt.1.e-6)then
          kcell(i,j)=0.
      elseif(wtd(i,j).lt.-1.5)then
          kcell(i,j)=fdepth(i,j)*klat(i,j)*exp((wtd(i,j)+1.5)/fdepth(i,j))
      else
          kcell(i,j)=klat(i,j)*(wtd(i,j)+1.5+fdepth(i,j))
      endif

      head(i,j) = topo(i,j) + wtd(i,j)
  enddo
enddo

!head=topo+wtd


do j=max(js+1,2),min(je-1,jmax-1)
  do i=max(is+1,2),min(ie-1,imax-1)
IF(landmask(i,j).eq.1) then

q=0.
qo18=0.
qin=0.
qout=0.
qino18=0.
qouto18=0.

!north
qn =    (kcell(i,j+1)+kcell(i,j)) &
        * (head(i,j+1)-head(i,j)) &
        * cos( d2r * (xlat(i,j) + 0.5*dxy) )

if(qn.gt.0.)then
        qno18 = qn *  o18wtd(i,j+1)
        qin = qin + qn
        qino18 = qino18 + qno18
else
        qno18 = qn *  o18wtd(i,j)
        qout = qout +qn
        qouto18 = qouto18 +qno18
endif

!south
qs =   (kcell(i,j-1)+kcell(i,j)) &
        *  (head(i,j-1)-head(i,j)) &
        * cos( d2r * (xlat(i,j) - 0.5*dxy) )

if(qs.gt.0.)then
        qso18 = qs *  o18wtd(i,j-1)
        qin = qin + qs
        qino18 = qino18 + qso18
else
        qso18 = qs *  o18wtd(i,j)
        qout = qout +qs
        qouto18 = qouto18 +qso18
endif

!west
qw =    (kcell(i-1,j)+kcell(i,j)) &
        * (head(i-1,j)-head(i,j)) &
        / cos( d2r * xlat(i,j) )

if(qw.gt.0.)then
        qwo18 = qw *  o18wtd(i-1,j)
        qin = qin + qw
        qino18 = qino18 + qwo18
else
        qwo18 = qw *  o18wtd(i,j)
        qout = qout +qw
        qouto18 = qouto18 +qwo18
endif

!east
qe =    (kcell(i+1,j)+kcell(i,j)) &
        * (head(i+1,j)-head(i,j)) &
        / cos( d2r * xlat(i,j) )

if(qe.gt.0.)then
        qeo18 = qe *  o18wtd(i+1,j)
        qin = qin + qe
        qino18 = qino18 + qeo18
else
        qeo18 = qe *  o18wtd(i,j)
        qout = qout +qe
        qouto18 = qouto18 +qeo18
endif        

q = qn + qs + qw + qe
qlat(i,j) =  0.5 * q * deltat / area(i,j)

qo18 = qno18 + qso18 + qwo18 + qeo18
qlato18(i,j) =  0.5 * qo18 * deltat / area(i,j)

qlatin(i,j) =  0.5 * qin * deltat / area(i,j)
qlatout(i,j) = -0.5 * qout * deltat / area(i,j)

qlatino18(i,j) =  0.5 * qino18 * deltat / area(i,j)
qlatouto18(i,j) = -0.5 * qouto18 * deltat / area(i,j)

ENDIF
   enddo
enddo


end subroutine lateralflow4

!     ******************************************************************

subroutine UPDATEWTD(nzg,slz,dz,wtd,qspring,totwater,smoi,smoieq,soiltextures,smoiwtd)
implicit none
integer :: nzg,iwtd,kwtd,nsoil,nsoil1,k,k1
real , dimension(nzg+1) :: slz
real , dimension(nzg) :: dz 
real :: wtd,qspring,wtdold,totwater,smoiwtd,maxwatup,maxwatdw,wgpmid,syielddw,dzup,tempk,fracliq,smoieqwtd
real, dimension(nzg) :: smoi,smoieq

integer, dimension(2) :: soiltextures
integer, dimension(nzg) :: soiltxt

where(slz.lt.-0.3)
     soiltxt=soiltextures(1)
elsewhere
     soiltxt=soiltextures(2)
endwhere



iwtd=1

!case 1: totwater > 0 (water table going up):
IF(totwater.gt.0.)then


         if(wtd.ge.slz(1))then

            do k=2,nzg
              if(wtd.lt.slz(k))exit
            enddo
            iwtd=k
            kwtd=iwtd-1
            nsoil=soiltxt(kwtd)

!max water that fits in the layer
            maxwatup=dz(kwtd)*(slmsts(nsoil)-smoi(kwtd))

            if(totwater.le.maxwatup)then
               smoi(kwtd) = smoi(kwtd) + totwater / dz(kwtd)
               smoi(kwtd) = min(smoi(kwtd),slmsts(nsoil))
               if(smoi(kwtd).gt.smoieq(kwtd))wtd = min ( ( smoi(kwtd)*dz(kwtd) &
                 - smoieq(kwtd)*slz(iwtd) + slmsts(nsoil)*slz(kwtd) ) / &
                     ( slmsts(nsoil)-smoieq(kwtd) ) , slz(iwtd) )
               totwater=0.
            else   !water enough to saturate the layer
              smoi(kwtd) = slmsts(nsoil)
              totwater=totwater-maxwatup
              k1=iwtd
              do k=k1,nzg+1
                 wtd = slz(k)
                 iwtd=k+1
                 if(k.eq.nzg+1)exit
                 nsoil=soiltxt(k)
                 maxwatup=dz(k)*(slmsts(nsoil)-smoi(k))
                 if(totwater.le.maxwatup)then
                   smoi(k) = smoi(k) + totwater / dz(k)
                   smoi(k) = min(smoi(k),slmsts(nsoil))
                   if(smoi(k).gt.smoieq(k))wtd = min ( ( smoi(k)*dz(k) &
                     - smoieq(k)*slz(iwtd) + slmsts(nsoil)*slz(k) ) / &
                     ( slmsts(nsoil)-smoieq(k) ) , slz(iwtd) )
                   totwater=0.
                   exit
                 else
                    smoi(k) = slmsts(nsoil)
                    totwater=totwater-maxwatup
                 endif

              enddo

            endif

         elseif(wtd.ge.slz(1)-dz(1))then ! wtd below bottom of soil model

            nsoil=soiltxt(1)
            maxwatup=(slmsts(nsoil)-smoiwtd)*dz(1)

            if(totwater.le.maxwatup)then
                smoieqwtd = slmsts(nsoil) * ( slpots(nsoil) / &
                    (slpots(nsoil) - dz(1)) ) ** (1./slbs(nsoil))
                smoieqwtd = max(smoieqwtd,soilcp(nsoil))

                smoiwtd = smoiwtd + totwater / dz(1)
                smoiwtd = min(smoiwtd,slmsts(nsoil))
                if(smoiwtd.gt.smoieqwtd)wtd = min( ( smoiwtd*dz(1) &
                 - smoieqwtd*slz(1) + slmsts(nsoil)*(slz(1)-dz(1)) ) / &
                     ( slmsts(nsoil)-smoieqwtd ) , slz(1) )
                totwater=0.
            else
                smoiwtd=slmsts(nsoil)
                totwater=totwater-maxwatup
                do k=1,nzg+1
                    wtd=slz(k)
                    iwtd=k+1
                    if(k.eq.nzg+1)exit
                    nsoil=soiltxt(k)
                    maxwatup=dz(k)*(slmsts(nsoil)-smoi(k))
                    if(totwater.le.maxwatup)then
                     smoi(k) = min(smoi(k) + totwater / dz(k),slmsts(nsoil))
                     if(smoi(k).gt.smoieq(k))wtd = min ( ( smoi(k)*dz(k) &
                        - smoieq(k)*slz(iwtd) + slmsts(nsoil)*slz(k) ) / &
                           ( slmsts(nsoil)-smoieq(k) ) , slz(iwtd) )
                     totwater=0.
                     exit
                    else
                     smoi(k) = slmsts(nsoil)
                     totwater=totwater-maxwatup
                    endif
                enddo
             endif

!deep water table
       else
            nsoil=soiltxt(1)
            maxwatup=(slmsts(nsoil)-smoiwtd)*(slz(1)-dz(1)-wtd)
            if(totwater.le.maxwatup)then
               wtd = wtd + totwater/(slmsts(nsoil)-smoiwtd)
               totwater=0.
            else
               totwater=totwater-maxwatup
               wtd=slz(1)-dz(1)
               maxwatup=(slmsts(nsoil)-smoiwtd)*dz(1)
              if(totwater.le.maxwatup)then
                smoieqwtd = slmsts(nsoil) * ( slpots(nsoil) / &
                    (slpots(nsoil) - dz(1)) ) ** (1./slbs(nsoil))
                smoieqwtd = max(smoieqwtd,soilcp(nsoil))

                smoiwtd = smoiwtd + totwater / dz(1)
                smoiwtd = min(smoiwtd,slmsts(nsoil))
                wtd = ( smoiwtd*dz(1) &
                 - smoieqwtd*slz(1) + slmsts(nsoil)*(slz(1)-dz(1)) ) / &
                     ( slmsts(nsoil)-smoieqwtd )
                totwater=0.
              else
                smoiwtd=slmsts(nsoil)
                totwater=totwater-maxwatup
                do k=1,nzg+1
                    wtd=slz(k)
                    iwtd=k+1
                    if(k.eq.nzg+1)exit
                    nsoil=soiltxt(k)
                    maxwatup=dz(k)*(slmsts(nsoil)-smoi(k))

                    if(totwater.le.maxwatup)then
                     smoi(k) = smoi(k) + totwater / dz(k)
                     smoi(k) = min(smoi(k),slmsts(nsoil))
                     if(smoi(k).gt.smoieq(k))wtd = ( smoi(k)*dz(k) &
                        - smoieq(k)*slz(iwtd) + slmsts(nsoil)*slz(k) ) / &
                           ( slmsts(nsoil)-smoieq(k) )
                     totwater=0.
                     exit
                    else
                     smoi(k) = slmsts(nsoil)
                     totwater=totwater-maxwatup
                    endif
                   enddo
               endif
             endif
         endif

!water springing at the surface
        qspring=totwater

!case 2: totwater < 0 (water table going down):
ELSEIF(totwater.lt.0.)then


         if(wtd.ge.slz(1))then !wtd in the resolved layers

            do k=2,nzg
               if(wtd.lt.slz(k))exit
            enddo
            iwtd=k

               k1=iwtd-1
               do kwtd=k1,1,-1

                  nsoil=soiltxt(kwtd)

!max water that the layer can yield
                  maxwatdw=dz(kwtd)*(smoi(kwtd)-smoieq(kwtd))

                  if(-totwater.le.maxwatdw)then
                        smoi(kwtd) = smoi(kwtd) + totwater / dz(kwtd)
                        if(smoi(kwtd).gt.smoieq(kwtd))then
                              wtd = ( smoi(kwtd)*dz(kwtd) &
                                 - smoieq(kwtd)*slz(iwtd) + slmsts(nsoil)*slz(kwtd) ) / &
                                 ( slmsts(nsoil)-smoieq(kwtd) )
                         else
                              wtd=slz(kwtd)
                              iwtd=iwtd-1
                         endif
                         totwater=0.
                         exit
                   else
                         wtd = slz(kwtd)
                         iwtd=iwtd-1
                         if(maxwatdw.ge.0.)then
                            smoi(kwtd) = smoieq(kwtd)
                            totwater = totwater + maxwatdw
                         endif
                   endif

                enddo

               if(iwtd.eq.1.and.totwater.lt.0.)then
                  nsoil=soiltxt(1)
                  smoieqwtd = slmsts(nsoil) * ( slpots(nsoil) / &
                      (slpots(nsoil) - dz(1)) ) ** (1./slbs(nsoil))
                  smoieqwtd = max(smoieqwtd,soilcp(nsoil))

                  maxwatdw=dz(1)*(smoiwtd-smoieqwtd)

                  if(-totwater.le.maxwatdw)then

                       smoiwtd = smoiwtd + totwater / dz(1)
                       wtd = max( ( smoiwtd*dz(1) &
                           - smoieqwtd*slz(1) + slmsts(nsoil)*(slz(1)-dz(1)) ) / &
                            ( slmsts(nsoil)-smoieqwtd ) , slz(1)-dz(1) )

                  else

                       wtd=slz(1)-dz(1)
                       smoiwtd = smoiwtd + totwater / dz(1)
!and now even further down
                       dzup=(smoieqwtd-smoiwtd)*dz(1)/(slmsts(nsoil)-smoieqwtd)
                       wtd=wtd-dzup
                       smoiwtd=smoieqwtd

                  endif

                endif



        elseif(wtd.ge.slz(1)-dz(1))then

!if wtd was already below the bottom of the resolved soil crust
            nsoil=soiltxt(1)
            smoieqwtd = slmsts(nsoil) * ( slpots(nsoil) / &
                    (slpots(nsoil) - dz(1)) ) ** (1./slbs(nsoil))
            smoieqwtd = max(smoieqwtd,soilcp(nsoil))

            maxwatdw=dz(1)*(smoiwtd-smoieqwtd)

            if(-totwater.le.maxwatdw)then

               smoiwtd = smoiwtd + totwater / dz(1)
               wtd = max( ( smoiwtd*dz(1) &
                    - smoieqwtd*slz(1) + slmsts(nsoil)*(slz(1)-dz(1)) ) / &
                    ( slmsts(nsoil)-smoieqwtd ) , slz(1)-dz(1) )

            else

               wtd=slz(1)-dz(1)
               smoiwtd = smoiwtd + totwater / dz(1)
!and now even further down
               dzup=(smoieqwtd-smoiwtd)*dz(1)/(slmsts(nsoil)-smoieqwtd)
               wtd=wtd-dzup
               smoiwtd=smoieqwtd

             endif

         else
!gmmequilibrium soil moisture content
               nsoil=soiltxt(1)
               wgpmid = slmsts(nsoil) * ( slpots(nsoil) / &
                    (slpots(nsoil) - (slz(1)-wtd)) ) ** (1./slbs(nsoil))
               wgpmid=max(wgpmid,soilcp(nsoil))
               syielddw=slmsts(nsoil)-wgpmid
               wtdold=wtd
               wtd = wtdold + totwater/syielddw
!update wtdwgp
               smoiwtd = (smoiwtd*(slz(1)-wtdold)+wgpmid*(wtdold-wtd) ) / (slz(1)-wtd)

          endif

          qspring=0.

ENDIF


end subroutine updatewtd
!     ******************************************************************
subroutine GW2RIVER(imax,jmax,is,ie,js,je,nzg,slz,deltat,soiltxt,landmask,wtd,maxdepth,riverdepth,width,length,area,fdepth,qrf)
implicit none
integer :: i,j,imax,jmax,is,ie,js,je,nsoil,k,iwtd,nzg
real, dimension(nzg+1) :: slz
integer ,dimension(2,is:ie,js:je) :: soiltxt
integer, dimension(is:ie,js:je) :: landmask
real, dimension(is:ie,js:je) :: wtd,maxdepth,riverdepth,width,length,area,qrf,fdepth
real :: riversurface,deltat,soilwatercap,rcond,rdepth,hydcon

!soilwatercap=0.
qrf=0.

  do j=js+1,je-1
      do i=max(is+1,2),min(ie-1,imax-1)
      soilwatercap=0.
           if(landmask(i,j).eq.0.or.width(i,j).eq.0.)cycle
             rdepth=max(riverdepth(i,j),0.)

             nsoil=soiltxt(2,i,j) 
             riversurface= -( maxdepth(i,j)-rdepth )
             if(riversurface.ge.0.)cycle      !this just in case...


             if(wtd(i,j).gt.riversurface)then


                  hydcon = slcons(nsoil)*max(min(exp((-maxdepth(i,j)+1.5)/fdepth(i,j)),1.),0.1)
                  rcond=width(i,j)*length(i,j)*hydcon
                  qrf(i,j)=rcond*(wtd(i,j)-riversurface) * ( deltat / area(i,j) )


!limit it to prevent sudden drops , lets say 50mm per day 0.05/86400.
                  qrf(i,j)=min(qrf(i,j),deltat*0.05/86400.)

             elseif(wtd(i,j).gt.-maxdepth(i,j))then   !water table connected to the river, even though below river surface

                  hydcon = slcons(nsoil)*max(min(exp((-maxdepth(i,j)+1.5)/fdepth(i,j)),1.),0.1)
                  rcond=width(i,j)*length(i,j)*hydcon

                  soilwatercap=-rcond*(wtd(i,j)-riversurface) * ( deltat / area(i,j) )
                  soilwatercap=min(soilwatercap,deltat*0.05/86400.)
                  qrf(i,j)=-max(min(soilwatercap,riverdepth(i,j)),0.)*min(width(i,j)*length(i,j)/area(i,j),1.)

             else
!water table below river bed, disconnected from the river. No rcond use, just
!infiltration. Assume it occurs at the Ksat rate and water goes directly to the
!water table.

                  qrf(i,j) = -max(min(slcons(nsoil)*deltat,rdepth),0.)  * min(width(i,j)*length(i,j)/area(i,j),1.)

             endif


      enddo
   enddo


end subroutine gw2river

!     ******************************************************************

subroutine RIVERS_KW_FLOOD(imax,jmax,is,ie,js,je,deltat,dtlr,fd,bfd,qnew,qs,qrf,delsfcwat &
                  ,slope,depth,width,length,maxdepth,area,riverarea,floodarea,riverchannel &
                  ,qmean,floodheight,topo)

implicit none
!integer, parameter :: ntsplit=15
!integer, parameter :: ntsplit=4
integer :: i,j,imax,jmax,js,je,is,ie,n,i1,j1,i2,j2
integer ,dimension(is:ie,js:je) :: fd,bfd
real, dimension(is:ie,js:je) :: q,qin,qnew,qs,qrf,qext,delsfcwat &
                  ,slope,depth,width,length,maxdepth,area &
                  ,riverarea,qmean,floodheight,riverchannel,floodarea,topo
real :: deltat,snew,aa,wi,speed,frwtd,dtlr,dsnew,flowwidth,slopeinst &
       ,dtopo,dcommon,qmax,vmax,waterelevij,waterelevi1j1,waterelevi2j2,slopefor,slopeback
integer :: reqsu,reqsd,reqru,reqrd


do j=max(js+1,2),min(je-1,jmax-1)
      do i=max(is+1,2),min(ie-1,imax-1)
IF(fd(i,j).ne.0) then

          qext(i,j)= ( qrf(i,j) + qs(i,j) +  delsfcwat(i,j) ) / deltat  * area(i,j)
!          riverarea(i,j) = width(i,j)*length(i,j)
!          floodarea(i,j) = max( area(i,j)-riverarea(i,j) , 0. )
!          riverchannel(i,j) = maxdepth(i,j)*riverarea(i,j)


ENDIF
   enddo
enddo


!dtlr = deltat/float(ntsplit)

!do n=1,ntsplit

if(numtasks.gt.1)call SENDBORDERS4(is,ie,js,je,qnew)

q=qnew

qin=0.

do j=js,je
  do i=is,ie
       if(fd(i,j).gt.0)then
             call flowdir(is,ie,js,je,fd,i,j,i1,j1)
             if(i1.gt.is.and.i1.lt.ie.and.j1.gt.js.and.j1.lt.je)then
                     qin(i1,j1) = qin(i1,j1) + q(i,j)
             endif
       endif
  enddo
enddo

do j=max(js+1,2),min(je-1,jmax-1)
      do i=max(is+1,2),min(ie-1,imax-1)

IF(fd(i,j).ne.0) then

!calculate total inflow into cell i j
!fd (flow direction) tells where the river in cell i j is flowing to

          dsnew = qin(i,j)-q(i,j)

!Taquari
          if(i.eq.4498.and.j.eq.4535)dsnew = dsnew + q(4499,4534)/4.
          if(i.eq.4498.and.j.eq.4534)dsnew = dsnew - q(4499,4534)/4.
!Taquari
          if(i.eq.4464.and.j.eq.4536)dsnew = dsnew + q(4465,4535)/2.
          if(i.eq.4465.and.j.eq.4534)dsnew = dsnew - q(4465,4535)/2.
!Taquari
          if(i.eq.4346.and.j.eq.4560)dsnew = dsnew + q(4346,4561)/3.
          if(i.eq.4345.and.j.eq.4561)dsnew = dsnew - q(4346,4561)/3.
!Taquari
          if(i.eq.4444.and.j.eq.4551)dsnew = dsnew + q(4444,4552)/3.
          if(i.eq.4443.and.j.eq.4553)dsnew = dsnew - q(4444,4552)/3.
!Taquari
          if(i.eq.4350.and.j.eq.4497)dsnew = dsnew + q(4352,4496)/3.
          if(i.eq.4351.and.j.eq.4496)dsnew = dsnew - q(4352,4496)/3.

!Sao Lourenco
          if(i.eq.4439.and.j.eq.4772)dsnew = dsnew + q(4440,4773)/2.
          if(i.eq.4440.and.j.eq.4772)dsnew = dsnew - q(4440,4773)/2.

          if(i.eq.4400.and.j.eq.4685)dsnew = dsnew + q(4401,4685)/2.
          if(i.eq.4400.and.j.eq.4684)dsnew = dsnew - q(4401,4685)/2.

          if(i.eq.4418.and.j.eq.4688)dsnew = dsnew + q(4418,4689)/5.
          if(i.eq.4417.and.j.eq.4689)dsnew = dsnew - q(4418,4689)/5.

          if(i.eq.4367.and.j.eq.4698)dsnew = dsnew + q(4368,4699)/6.
          if(i.eq.4368.and.j.eq.4698)dsnew = dsnew - q(4368,4699)/6.

          if(i.eq.4363.and.j.eq.4667)dsnew = dsnew + q(4364,4668)/6.
          if(i.eq.4364.and.j.eq.4667)dsnew = dsnew - q(4364,4668)/6.

          if(i.eq.4475.and.j.eq.4718)dsnew = dsnew + q(4475,4717)/6.
          if(i.eq.4474.and.j.eq.4717)dsnew = dsnew - q(4475,4717)/6.

!new river store

          snew = depth(i,j)*riverarea(i,j) + floodheight(i,j)*floodarea(i,j) + ( dsnew+qext(i,j) ) * dtlr


!now redistribute water between river channel and floodplain and calculate new
!riverdepth and floodheight
if(snew.ne.snew)write(6,*)'problem with snew',i,j,dsnew,floodheight(i,j),depth(i,j),qext(i,j)
          if(snew.ge.riverchannel(i,j))then

              floodheight(i,j) = (snew-riverchannel(i,j)) / max(area(i,j),riverarea(i,j))
              depth(i,j) = floodheight(i,j) + maxdepth(i,j)

          else

              floodheight(i,j) = 0.
              if(riverarea(i,j).gt.0.)then
                        depth(i,j) = snew/riverarea(i,j)
              else
                        depth(i,j)=0.
              endif


          endif
if(depth(i,j).ne.depth(i,j))write(6,*)'problem with depth',i,j,qrf(i,j),qs(i,j),delsfcwat(i,j),qnew(i,j),floodheight(i,j)

ENDIF
   enddo
enddo


if(numtasks.gt.1)call SENDBORDERS4(is,ie,js,je,depth)


do j=js+1,je-1
  do i=is+1,ie-1

          if(fd(i,j).ne.0)then

             if(width(i,j)*depth(i,j).gt.1.e-9.and.fd(i,j).gt.0)then
!calculate speed from manning's formula
!               if(width(i,j).lt.2..and.floodheight(i,j).gt.0.05)then !it moves like a sheet
!                  aa=floodheight(i,j)
!                  flowwidth=sqrt(area(i,j))
!               else
                  aa=depth(i,j)*width(i,j)/(2.*depth(i,j)+width(i,j))
                  flowwidth=width(i,j)
!               endif
               if(floodheight(i,j).gt.0.05)then
                  call flowdir(is,ie,js,je,fd,i,j,i1,j1)
                  waterelevij=topo(i,j)-maxdepth(i,j)+depth(i,j)
                  waterelevi1j1=topo(i1,j1)-maxdepth(i1,j1)+max(depth(i1,j1),0.)
                  slopefor=( waterelevij - waterelevi1j1 ) / (0.5*(length(i,j)+length(i1,j1)))
                  if(bfd(i,j).gt.0)then
                     call flowdir(is,ie,js,je,bfd,i,j,i2,j2)
                     waterelevi2j2=topo(i2,j2)-maxdepth(i2,j2)+max(depth(i2,j2),0.)
                     slopeback=( waterelevi2j2 - waterelevij ) / (0.5*(length(i2,j2)+length(i,j)))
                     slopeinst = 0.5*(slopefor+slopeback)
                  else
                     slopeinst = slopefor
                  endif

!                  slopeinst=0.5*(slopeinst+slope(i,j))
                  slopeinst=0.25*slopeinst+0.75*slope(i,j)
!                  slopeinst=0.1*slopeinst+0.9*slope(i,j)
                  if(slopeinst.lt.0.)slopeinst=slope(i,j)

!                  dtopo=max(waterelevij-waterelevi1j1,0.)
!                  qmax = dtopo*riverarea(i,j)/dtlr
!                  vmax = qmax / (depth(i,j)*width(i,j))

                  speed = ( aa**(2./3.) )*sqrt(slopeinst)/0.03

!                  vmax=max(vmax,( aa**(2./3.) )*sqrt(slope(i,j))/0.03)
!                  speed=max(min(speed,vmax),0.01)
                   speed=max(min(speed,length(i,j)/dtlr),0.01)


               else
                  slopeinst=slope(i,j)                  
               endif
               speed = ( aa**(2./3.) )*sqrt(slopeinst)/0.03
               speed=max(min(speed,length(i,j)/dtlr),0.01)
             else
               speed=0.
             endif

!now calculate the new q
              qnew(i,j) = speed * depth(i,j) * flowwidth!width(i,j)

           else

              qnew(i,j)=0.

           endif


  enddo
enddo

qmean = qmean + qnew*dtlr


!enddo


end subroutine rivers_kw_flood

!******************************************************************************************
subroutine RIVERS_DW_FLOOD(imax,js,je,deltat,dtlr,fd,bfd,qnew,qs,qrf,delsfcwat &
                  ,slope,depth,width,length,maxdepth,area,riverarea,floodarea,riverchannel &
                  ,qmean,floodheight,topo)

implicit none
real , parameter :: gg = 9.81
!integer, parameter :: ntsplit=15
!integer, parameter :: ntsplit=4
integer :: i,j,imax,js,je,n,i1,j1,i2,j2
integer ,dimension(imax,js:je) :: fd,bfd
real, dimension(imax,js:je) :: q,qin,qnew,qs,qrf,qext,delsfcwat &
                  ,slope,depth,width,length,maxdepth,area &
                  ,riverarea,qmean,floodheight,riverchannel,floodarea,topo
real :: deltat,snew,aa,wi,speed,frwtd,dtlr,dsnew,flowwidth,slopeinst &
       ,dtopo,dcommon,qmax,vmax,waterelevij,waterelevi1j1,waterelevi2j2,slopefor,slopeback
integer :: reqsu,reqsd,reqru,reqrd


do j=js+1,je-1
  do i=2,imax-1
IF(fd(i,j).ne.0) then

          qext(i,j)= ( qrf(i,j) + qs(i,j) +  delsfcwat(i,j) ) / deltat  * area(i,j)
!          riverarea(i,j) = width(i,j)*length(i,j)
!          floodarea(i,j) = max( area(i,j)-riverarea(i,j) , 0. )
!          riverchannel(i,j) = maxdepth(i,j)*riverarea(i,j)



ENDIF
   enddo
enddo


!dtlr = deltat/float(ntsplit)

!do n=1,ntsplit

   if(numtasks.gt.1)call sendborders(imax,js,je,qnew,reqsu,reqsd,reqru,reqrd)

!make sure that the borders are received before calculating anything
   if(pid.eq.1)then
       call  MPI_wait(reqru,status,ierr)
   elseif(pid.eq.numtasks-2)then
       call  MPI_wait(reqrd,status,ierr)
   elseif(pid.gt.1.and.pid.lt.numtasks-2)then
      call  MPI_wait(reqru,status,ierr)
      call  MPI_wait(reqrd,status,ierr)
   endif

q=qnew

qin=0.

do j=js,je
  do i=1,imax
       if(fd(i,j).gt.0)then
             call flowdir(1,imax,js,je,fd,i,j,i1,j1)
             if(i1.gt.1.and.i1.lt.imax.and.j1.gt.js.and.j1.lt.je)then
                     qin(i1,j1) = qin(i1,j1) + q(i,j)
             endif
       endif
  enddo
enddo


do j=js+1,je-1
  do i=2,imax-1

IF(fd(i,j).ne.0) then

!calculate total inflow into cell i j
!fd (flow direction) tells where the river in cell i j is flowing to

          dsnew = qin(i,j)-q(i,j)

!Taquari
          if(i.eq.4498.and.j.eq.4535)dsnew = dsnew + q(4499,4534)/4.
          if(i.eq.4498.and.j.eq.4534)dsnew = dsnew - q(4499,4534)/4.
!Taquari
          if(i.eq.4464.and.j.eq.4536)dsnew = dsnew + q(4465,4535)/2.
          if(i.eq.4465.and.j.eq.4534)dsnew = dsnew - q(4465,4535)/2.
!Taquari
          if(i.eq.4346.and.j.eq.4560)dsnew = dsnew + q(4346,4561)/3.
          if(i.eq.4345.and.j.eq.4561)dsnew = dsnew - q(4346,4561)/3.
!Taquari
          if(i.eq.4444.and.j.eq.4551)dsnew = dsnew + q(4444,4552)/3.
          if(i.eq.4443.and.j.eq.4553)dsnew = dsnew - q(4444,4552)/3.
!Taquari
          if(i.eq.4350.and.j.eq.4497)dsnew = dsnew + q(4352,4496)/3.
          if(i.eq.4351.and.j.eq.4496)dsnew = dsnew - q(4352,4496)/3.

!Sao Lourenco
          if(i.eq.4439.and.j.eq.4772)dsnew = dsnew + q(4440,4773)/2.
          if(i.eq.4440.and.j.eq.4772)dsnew = dsnew - q(4440,4773)/2.

          if(i.eq.4400.and.j.eq.4685)dsnew = dsnew + q(4401,4685)/2.
          if(i.eq.4400.and.j.eq.4684)dsnew = dsnew - q(4401,4685)/2.

          if(i.eq.4418.and.j.eq.4688)dsnew = dsnew + q(4418,4689)/5.
          if(i.eq.4417.and.j.eq.4689)dsnew = dsnew - q(4418,4689)/5.

          if(i.eq.4367.and.j.eq.4698)dsnew = dsnew + q(4368,4699)/6.
          if(i.eq.4368.and.j.eq.4698)dsnew = dsnew - q(4368,4699)/6.

          if(i.eq.4363.and.j.eq.4667)dsnew = dsnew + q(4364,4668)/6.
          if(i.eq.4364.and.j.eq.4667)dsnew = dsnew - q(4364,4668)/6.

          if(i.eq.4475.and.j.eq.4718)dsnew = dsnew + q(4475,4717)/6.
          if(i.eq.4474.and.j.eq.4717)dsnew = dsnew - q(4475,4717)/6.

!new river store

          snew = depth(i,j)*riverarea(i,j) + floodheight(i,j)*floodarea(i,j) + ( dsnew+qext(i,j) ) * dtlr


!now redistribute water between river channel and floodplain and calculate new
!riverdepth and floodheight
if(snew.ne.snew)write(6,*)'problem with snew',i,j,dsnew,qin(i,j),q(i,j),floodheight(i,j),depth(i,j),qext(i,j)
          if(snew.ge.riverchannel(i,j))then

              floodheight(i,j) = (snew-riverchannel(i,j)) / max(area(i,j),riverarea(i,j))
              depth(i,j) = floodheight(i,j) + maxdepth(i,j)

          else

              floodheight(i,j) = 0.
              if(riverarea(i,j).gt.0.)then
                        depth(i,j) = snew/riverarea(i,j)
              else
                        depth(i,j)=0.
              endif


          endif
if(depth(i,j).ne.depth(i,j))write(6,*)'problem with depth',i,j,qrf(i,j),qs(i,j),delsfcwat(i,j),qnew(i,j),floodheight(i,j)

ENDIF
   enddo
enddo


!before changing qnew make sure that the borders have been received
   if(pid.eq.1)then
       call  MPI_wait(reqsu,status,ierr)
   elseif(pid.eq.numtasks-2)then
       call  MPI_wait(reqsd,status,ierr)
   elseif(pid.gt.1.and.pid.lt.numtasks-2)then
      call  MPI_wait(reqsu,status,ierr)
      call  MPI_wait(reqsd,status,ierr)
   endif

if(numtasks.gt.1)call sendborders(imax,js,je,depth,reqsu,reqsd,reqru,reqrd)

!make sure that the borders are received before calculating anything
   if(pid.eq.1)then
       call  MPI_wait(reqru,status,ierr)
   elseif(pid.eq.numtasks-2)then
       call  MPI_wait(reqrd,status,ierr)
   elseif(pid.gt.1.and.pid.lt.numtasks-2)then
      call  MPI_wait(reqru,status,ierr)
      call  MPI_wait(reqrd,status,ierr)
   endif


do j=js+1,je-1
  do i=2,imax-1

          if(fd(i,j).gt.0)then

                  call flowdir(1,imax,js,je,fd,i,j,i1,j1)
              if(floodheight(i,j).gt.0.05.or.depth(i1,j1).gt.maxdepth(i1,j1)+0.05)then
           
                      if(width(i,j).gt.0)then
                          aa=depth(i,j)*width(i,j)/(2.*depth(i,j)+width(i,j))
                      else
                          aa=depth(i,j)
                      endif

                  waterelevij=topo(i,j)-maxdepth(i,j)+depth(i,j)
                  waterelevi1j1=topo(i1,j1)-maxdepth(i1,j1)+max(depth(i1,j1),0.)
                  slopefor=( waterelevi1j1 - waterelevij ) / (0.5*(length(i,j)+length(i1,j1)))
                  if(bfd(i,j).gt.0)then
                     call flowdir(1,imax,js,je,bfd,i,j,i2,j2)
                     waterelevi2j2=topo(i2,j2)-maxdepth(i2,j2)+max(depth(i2,j2),0.)
                     slopeback=( waterelevij - waterelevi2j2 ) / (0.5*(length(i2,j2)+length(i,j)))
                     slopeinst = 0.5*(slopefor+slopeback)
                  else
                     slopeinst = slopefor
                  endif


                  qnew(i,j) = ( q(i,j) - gg * depth(i,j) * dtlr * slopeinst ) / &
                              ( 1. + gg * dtlr * 0.03**2. * q(i,j) / ( aa**(4./3.) * depth(i,j)) )

                  if(width(i,j).eq.0.)then
                        flowwidth=sqrt(area(i,j))
                  else
                        flowwidth=width(i,j)
                  endif
    
                  qnew(i,j) = qnew(i,j) * flowwidth


              else
               aa=depth(i,j)*width(i,j)/(2.*depth(i,j)+width(i,j))
               speed = ( aa**(2./3.) )*sqrt(slope(i,j))/0.03
               speed=max(min(speed,length(i,j)/dtlr),0.01)

!now calculate the new q
              qnew(i,j) = speed * depth(i,j) * width(i,j)

              endif

           else

              qnew(i,j)=0.

           endif


  enddo
enddo

qmean = qmean + qnew*dtlr

!before changing depth make sure that the borders have been received
   if(pid.eq.1)then
       call  MPI_wait(reqsu,status,ierr)
   elseif(pid.eq.numtasks-2)then
       call  MPI_wait(reqsd,status,ierr)
   elseif(pid.gt.1.and.pid.lt.numtasks-2)then
      call  MPI_wait(reqsu,status,ierr)
      call  MPI_wait(reqsd,status,ierr)
   endif



!enddo


end subroutine rivers_dw_flood

!******************************************************************************************


subroutine FLOODING(imax,jmax,is,ie,js,je,deltat,fd,bfd,topo,area,riverwidth,riverlength,riverdepth,floodheight,delsfcwat) 
!use module_parallel
implicit none

integer, parameter :: ntsplit=1
integer :: imax,jmax,is,ie,js,je,i,j,i1,j1,i2,j2,ilow,jlow,ii,jj,k,ksn,n
integer, dimension(is:ie,js:je) :: fd,bfd
real, dimension(is:ie,js:je) :: topo,area,floodheight,dflood,dflood2,delsfcwat,riverwidth,riverlength,riverdepth
real, dimension(is:ie) :: borderu,borderd
real, dimension(js:je) :: borderl,borderr
real :: deltat,dh,dhmax,dij,dtotal
integer :: reqsu,reqsd,reqru,reqrd,reqsu2,reqsd2,reqru2,reqrd2


dflood=0.
dflood2=0.

DO n=1,ntsplit

!communicate flood water height to neighboring cells

if(numtasks.gt.1)call SENDBORDERS4(is,ie,js,je,floodheight)


   do j=max(js+1,2),min(je-1,jmax-1)
      do i=max(is+1,2),min(ie-1,imax-1)


         if(fd(i,j).eq.0)cycle
         if(floodheight(i,j).gt.0.05)then

!                   call flowdir(imax,js,je,fd,i,j,i1,j1)
!                   call flowdir(imax,js,je,bfd,i,j,i2,j2)

!find the lowest elevation neighbour that is not along the main river channel
          dhmax=0.
          dh=0.
          ilow=i
          jlow=j
          do jj=j-1,j+1
             do ii=i-1,i+1
!                   if(ii.eq.i1.and.jj.eq.j1)cycle
!                   if(ii.eq.i2.and.jj.eq.j2)cycle
                   if(ii.eq.i.and.jj.eq.j)cycle

                   dh=floodheight(i,j)+topo(i,j)-(floodheight(ii,jj)+topo(ii,jj))
                   if(ii.ne.i.and.jj.ne.j)dh=dh/sqrt(2.)
                   if(dh.gt.dhmax)then
                         ilow=ii
                         jlow=jj
                         dhmax=dh
                   endif
             enddo
          enddo
!now flood the lowest elevation neighbour

        if(dhmax.gt.0.)then
         call flowdir(is,ie,js,je,fd,i,j,i1,j1)

         dtotal=floodheight(i,j)+floodheight(ilow,jlow)
!         dij=max(0.5*(topo(ilow,jlow)-topo(i,j)+dtotal),0.)
!         dflood(i,j)=dflood(i,j)+dij-floodheight(i,j)
!         dflood(ilow,jlow)=dflood(ilow,jlow)+(dtotal-dij)-floodheight(ilow,jlow)
         dij = max( floodheight(i,j)-max(0.5*(topo(ilow,jlow)-topo(i,j)+dtotal),0.) , 0.)
         if(ilow.eq.i1.and.jlow.eq.j1) &
           dij=max(dij-(riverwidth(i,j)*floodheight(i,j)*riverlength(i,j))/area(i,j),0.) !the flow along the river channel is taken care of by the river routine
         if(delsfcwat(i,j).lt.0.)dij=max(min(dij,floodheight(i,j)+delsfcwat(i,j)),0.)
         dflood(i,j) = dflood(i,j) - dij
         dflood(ilow,jlow) = dflood(ilow,jlow) + dij*area(i,j)/area(ilow,jlow)
        endif


         endif

      enddo
   enddo

if(numtasks.gt.1)then
   call SENDBORDERSFLOOD4(is,ie,js,je,dflood,borderu,borderd,borderl,borderr)

   dflood(is:ie,js+1)  = dflood(is:ie,js+1) +  borderd(is:ie) 
   dflood(is:ie,je-1)  = dflood(is:ie,je-1) +  borderu(is:ie)
   dflood(is+1,js:je)  = dflood(is+1,js:je) +  borderl(js:je)
   dflood(ie-1,js:je)  = dflood(ie-1,js:je) +  borderr(js:je)

!now the corners
   dflood(is+1,js+1) = dflood(is+1,js+1) + borderl(js)
   dflood(is+1,je-1) = dflood(is+1,je-1) + borderl(je)
   dflood(ie-1,js+1) = dflood(ie-1,js+1) + borderr(js)
   dflood(ie-1,je-1) = dflood(ie-1,je-1) + borderr(je)
endif


!update floodheight and riverdepth
     delsfcwat=delsfcwat+dflood
!     floodheight=floodheight+delsfcwat
!     riverdepth=riverdepth+delsfcwat
!     delsfcwat=0.

ENDDO

end subroutine flooding

!******************************************************************************************
subroutine MOVEQRF(imax,js,je,fd,qrf,area,width)
integer :: imax,js,je,i,j,ii,jj,iout,jout
integer, dimension(imax,js:je) :: fd
real, dimension(imax,js:je) :: qrf,area,width,qrfextra,qrfextra2
integer :: reqsu2,reqsd2,reqru2,reqrd2

qrfextra=0.

do j=js+1,je-1
  do i=2,imax-1
IF(fd(i,j).gt.0) then
    if(width(i,j).lt.1.)then
          call flowdir(1,imax,js,je,fd,i,j,iout,jout)
          qrfextra(iout,jout)=qrfextra(iout,jout)+qrf(i,j)*area(i,j)/area(iout,jout)
          qrf(i,j)=0.
     endif
ENDIF
   enddo
enddo   

if(numtasks.gt.1)then
   qrfextra2=qrfextra
   call sendbordersflood(imax,js,je,qrfextra2,reqsu2,reqsd2,reqru2,reqrd2)
endif

!make sure that the borders are received before calculating anything
   if(pid.eq.1)then
       call  MPI_wait(reqru2,status,ierr)
   elseif(pid.eq.numtasks-2)then
       call  MPI_wait(reqrd2,status,ierr)
   elseif(pid.gt.1.and.pid.lt.numtasks-2)then
      call  MPI_wait(reqru2,status,ierr)
      call  MPI_wait(reqrd2,status,ierr)
   endif

   if(pid.eq.1)then
           qrfextra(1:imax,je-1)  = qrfextra(1:imax,je-1) +  qrfextra2(1:imax,je-1)
   elseif(pid.eq.numtasks-2)then
           qrfextra(1:imax,js+1)  = qrfextra(1:imax,js+1) +  qrfextra2(1:imax,js+1)
   elseif(pid.gt.1.and.pid.lt.numtasks-2)then
           qrfextra(1:imax,js+1)  = qrfextra(1:imax,js+1) +  qrfextra2(1:imax,js+1)
           qrfextra(1:imax,je-1)  = qrfextra(1:imax,je-1) +  qrfextra2(1:imax,je-1)
   endif

!change qrf
   qrf = qrf + qrfextra

!before changing qrfextra make sure that the borders have been received
   if(pid.eq.1)then
       call  MPI_wait(reqsu2,status,ierr)
   elseif(pid.eq.numtasks-2)then
       call  MPI_wait(reqsd2,status,ierr)
   elseif(pid.gt.1.and.pid.lt.numtasks-2)then
      call  MPI_wait(reqsu2,status,ierr)
      call  MPI_wait(reqsd2,status,ierr)
   endif


end subroutine moveqrf
!******************************************************************************************
subroutine FLOWDIR(is,ie,js,je,fd,ii,jj,i,j)
implicit none
integer :: is,ie,js,je,i,j,ii,jj
integer, dimension(is:ie,js:je) :: fd

select case(fd(ii,jj))
  case(2,4,8)
      j=jj-1
  case(1,16)
      j=jj
  case(32,64,128)
      j=jj+1
  case default
      j=0
!      write(6,*)'i dont know what to do i',fd(ii,jj),ii,jj
end select

select case(fd(ii,jj))
   case(128,1,2)
       i=ii+1
   case(4,64)
       i=ii
   case(8,16,32)
       i=ii-1
  case default
       i=0
!      write(6,*)'i dont know what to do j',fd(ii,jj),ii,jj
end select

end subroutine flowdir

!******************************************************************************************



END MODULE MODULE_WTABLE
