MODULE module_rootdepth


implicit none

integer, parameter ::nvtyp=30,nstyp=13
real, save, dimension(nstyp) :: slmsts,soilcp,slbs,slcons,slpots,slwilt,klatfactor
data slmsts/0.395, 0.410, 0.435, 0.485, 0.451, 0.420  &
           ,0.477, 0.476, 0.426, 0.492, 0.482, 0.863, 0.476/
!data fieldcp/.135,.150,.195,.255,.240,.255,.322,.325  &
!            ,.310,.370,.367,.535,.325/
data soilcp/.050  ,.052  ,.092  ,.170  ,.125  ,.148 &
           ,.195  ,.235  ,.202  ,.257  ,.268  ,.195 ,.235/
data slbs  /4.05, 4.38, 4.9, 5.3, 5.39, 7.12, 7.75, 8.52  &
           ,10.4, 10.4, 11.4, 7.75, 8.52/
data slcons /.000176   ,.0001563  ,.00003467  &
            ,.0000072  ,.00000695 ,.0000063  &
            ,.0000017  ,.00000245 ,.000002167  &
            ,.000001033,.000001283,.0000080,.000005787/
!2m/day            ,.0000017  ,.000023148 ,.000002167  &
!2m/day            ,.000001033,.000023148,.0000080/
!1m/day            ,.0000017  ,.000011574 ,.000002167  &
!1m/day            ,.000001033,.000011574,.0000080/
!0.5m/day           ,.000001033,.000005787,.0000080/
data slpots/-0.121, -0.090, -0.218, -0.786, -0.478, -0.299  &
           ,-0.356, -0.630, -0.153, -0.490, -0.405, -0.356, -0.630/
data klatfactor /2.,3.,4.,10.,12.,14.,20.,24.,28.,40.,48.,48.,48./
!data klatfactor /2.,3.,4.,10.,12.,14.,20.,100.,28.,40.,100.,48./
!data klatfactor /2.,3.,4.,10.,12.,14.,20.,48.,28.,40.,48.,48./

CONTAINS

SUBROUTINE ROOTDEPTH(freedrain,is,ie,js,je,nzg,slz,dz,deltat,landmask,veg,hveg,soiltxt,wind,temp,qair,press,netrad,rshort &
                     ,lai,precip,qsrun,smoi,smoieq,smoiwtd,wtd,waterdeficit,watext,watextdeep,rech,deeprech &
                     ,et_s,et_i,et_c,intercepstore,ppacum,pppendepth,pppendepthold &
                     ,qlat,qlatsum,qsprings,inactivedays,maxinactivedays,fieldcp,fdepth,steps,floodheight &
                     ,qrf,delsfcwat,icefactor,wtdflux,et_s_daily,et_c_daily,transptop,infilk,infilflux,infilfluxday,infilcounter,hour &
                     ,o18,o18ratiopp,tempsfc,qlato18,transpo18,upflux )

!real, parameter :: minpprate=1./3. !pp (ammount in mm per timestep) above which there is no intercpetion loss
real, parameter :: minpprate=0.01 !pp (ammount in mm per timestep) above which there is no intercpetion loss
integer :: is,ie,js,je,nzg,i,j,k,freedrain,itime,maxinactivedays,floodflag,hour
real :: deltat,steps
real, dimension(nzg,nstyp) :: fieldcp
real, dimension(nzg+1) :: slz,flux
real, dimension(0:nzg+1) :: qlatflux
integer, dimension(0:nzg+1,is:ie,js:je) :: inactivedays
integer*1, dimension(is:ie,js:je,26:40) :: icefactor
integer*1, dimension(nzg) :: icefac
integer*1, dimension(is:ie,js:je) :: infilk,pppendepthold
real, dimension(nzg) :: dz,dsmoi
integer, dimension(is:ie,js:je) :: landmask
real, dimension(is:ie,js:je) :: veg,hveg,wind,temp,qair,press,netrad,rshort,lai,precip,qsrun,ppacum,waterdeficit,intercepstore &
        ,et_s,et_i,et_c,watextdeep,pppendepth,qlat,qlato18,qlatsum,qsprings,floodheight,qrf,delsfcwat
real, dimension(is:ie,js:je) ::  wtdflux,et_s_daily,et_c_daily,transptop,o18ratiopp,tempsfc,transpo18
integer, dimension(2,is:ie,js:je) :: soiltxt
real, dimension(nzg,is:ie,js:je) :: smoi,watext,smoieq,infilflux,infilfluxday,o18,upflux
integer*2, dimension(nzg,is:ie,js:je) :: infilcounter

real :: petstep_s,petstep_c,petstep_w,petstep_i,etstep_s,etstep_c,etstep_i,runoff,rechstep,ppdrip,watdef &
       ,dsmoideep,qlatstep,qlato18step,pppendepthstep,qrfstep,qrfcorrect,floodstep,wtdold,transpo18step
real :: delta,gamma,lambda,ra_a,ra_c,rs_c,R_a,R_s,petfactor_s,petfactor_c
real, dimension(is:ie,js:je) :: smoiwtd,wtd,rech,deeprech,fdepth
integer*1 :: infilkstep

!maxinactivedays = 30*8*nint(steps)   !30 days * 8 3h periods * steps in the rootactivy calculation

!smoiwtd=0.3
!wtd=0.
!deeprech=0.
icefac=0

DO j=js+1,je-1
  DO i=is+1,ie-1

if(landmask(i,j).eq.0)cycle

!       ppacum(i,j) = ppacum(i,j) + precip(i,j)

!gmm calculate PET

!if(i.eq.2761.and.j.eq.571)write(6,*)'temp,rad,press,qair,rshort,wind',temp(i,j),netrad(i,j),press(i,j),qair(i,j),rshort(i,j),wind(i,j)

!     call potevap_priestly_taylor(i,j,temp(i,j),rad(i,j),press(i,j),petstep)
!     call potevap_Penman_Monteith(i,j,temp(i,j),netrad(i,j),rshort(i,j),press(i,j),qair(i,j) &
!                                  ,wind(i,j),lai(i,j),veg(i,j),hveg(i,j),petstep)

      icefac(26:40)=icefactor(i,j,26:40)

      if(floodheight(i,j).gt.0.05)then
          floodflag=1
      else
          floodflag=0
      endif

      call potevap_Shutteworth_Wallace(i,j,deltat,temp(i,j),netrad(i,j),rshort(i,j),press(i,j),qair(i,j) &
                                  ,wind(i,j),lai(i,j),veg(i,j),hveg(i,j) &
                                  ,delta,gamma,lambda,ra_a,ra_c,rs_c,R_a,R_s &
!                                  ,petstep_s,petstep_c,petstep_w,petstep_i,floodflag)
                                  ,petfactor_s,petfactor_c,petstep_w,petstep_i,floodflag)

      et_s(i,j) = et_s(i,j) + petstep_w
      if(floodflag.eq.1.and.nint(veg(i,j)).le.1)delsfcwat(i,j) = delsfcwat(i,j) - petstep_w *1.e-3

if(nint(veg(i,j)).le.1)cycle

!if(i.eq.2761.and.j.eq.571)write(6,*)'pet',petstep,precip(i,j)

!gmm first interception

      call interception(minpprate,precip(i,j),lai(i,j),intercepstore(i,j),ppdrip,petstep_i,etstep_i)

      et_i(i,j) = et_i(i,j) + etstep_i

!gmm then extraction
!gmm now see where pet has to be transpired

ppdrip=ppdrip/steps !in mm
floodstep = floodheight(i,j)/steps !in m
!petstep_s=petstep_s/steps !in mm
!petstep_c=petstep_c/steps !in mm
qlatstep=qlat(i,j)/steps !in m
qlato18step=qlato18(i,j)/steps !in m
qrfstep=qrf(i,j)/steps !in m


flux=0.
qlatflux=0.

wtdold=wtd(i,j)

do itime=1,nint(steps)

     call extraction(i,j,nzg,slz,dz,deltat/steps,soiltxt(1,i,j),wtd(i,j),smoi(1,i,j),smoiwtd(i,j) &
                    ,delta,gamma,lambda,lai(i,j),ra_a,ra_c,rs_c,R_a,R_s,petfactor_s,petfactor_c,petstep_s & 
                    ,petstep_c,watdef,dsmoi,dsmoideep,inactivedays(0,i,j),maxinactivedays,fieldcp,hveg(i,j),fdepth(i,j) &
                    ,icefac)

     et_c(i,j) = et_c(i,j) + petstep_c - watdef*1.e3
     waterdeficit(i,j) = waterdeficit(i,j) + watdef*1.e3
     watext(:,i,j) = watext(:,i,j) + dsmoi(:)*1.e3
     transptop(i,j) = transptop(i,j) + dsmoi(nzg)*1.e3
     et_c_daily(i,j) = et_c_daily(i,j) + petstep_c - watdef*1.e3
!     watextdeep(i,j) = watextdeep(i,j) + dsmoideep*1.e3

!now update soil moisture from transpiration, evaporation, infiltration and soil
!fluxes

!dsmoi=dsmoi/steps
!dsmoideep=dsmoideep/steps
!ppdrip=ppdrip/steps
!petstep_s=petstep_s/steps

!do itime=1,36


      call soilfluxes(i,j,nzg,freedrain,deltat/steps,slz,dz,soiltxt(1,i,j),smoiwtd(i,j),dsmoi,dsmoideep  &
                      ,smoi(1,i,j),wtd(i,j),rechstep,deeprech(i,j),ppdrip,petstep_s,etstep_s,runoff,flux &
                      ,fdepth(i,j),qlatstep,qlatflux,qrfstep,qrfcorrect,floodstep,icefac &
                      ,smoieq(1,i,j),o18(1,i,j),o18ratiopp(i,j),tempsfc(i,j),qlato18step,transpo18step)

       delsfcwat(i,j) = delsfcwat(i,j) - max(floodstep-runoff,0.) !in m
       qsrun(i,j) = qsrun(i,j) + max(runoff-floodstep,0.) !in m
       rech(i,j) = rech(i,j) + rechstep*1.e3
       et_s(i,j) = et_s(i,j) + etstep_s
       transpo18(i,j) = transpo18(i,j) + transpo18step*1.e3
       et_s_daily(i,j) = et_s_daily(i,j) + etstep_s
       ppacum(i,j) = ppacum(i,j) + ppdrip
!correct qrf. qrfstep should be zero after soilfluxes if there is no problem
       qrf(i,j) = qrf(i,j) + qrfcorrect

!       do k=1,nzg
!          smoimax(k,i,j)=max(smoimax(k,i,j),smoi(k,i,j))
!          smoimin(k,i,j)=min(smoimin(k,i,j),smoi(k,i,j))
!       enddo

!now adjust wtd

     call updateshallowwtd(i,j,nzg,freedrain,slz,dz,soiltxt(1,i,j),smoieq(1,i,j),smoiwtd(i,j),smoi(1,i,j),wtd(i,j),rechstep,fdepth(i,j))

       rech(i,j) = rech(i,j) + rechstep*1.e3 



!       wtdflux(i,j) = wtdflux(i,j) + (rechstep - qlatstep + qrfstep + qrfcorrect) * 1e3


!               call updatewtdqlat(nzg,slz,dz,wtd(i,j),runoff,qlatstep,smoi(1,i,j) &
!                      ,smoieq(1,i,j),soiltxt(1,i,j),smoiwtd(i,j),qlatflux,fdepth(i,j))
!               qsrun(i,j) = qsrun(i,j) + runoff*1.e3
!               qsprings(i,j) = qsprings(i,j) + runoff*1.e3
               qlatsum(i,j)=qlatsum(i,j)+qlatstep

enddo


!save infiltration
!       do k=nzg,0,-1
!         if(flux(k+1).lt.-0.333e-5)then  !since the timestep was reduced from 3 to 1 h, change the threshold accordingly
!           if(k.eq.0)then
!              if(-flux(1).gt.-qlatflux(1))then
!                    infilflux(k,i,j) = infilflux(k,i,j) + max(-flux(k+1),0.)*1.e3
!                    infilcounter(k,i,j)=infilcounter(k,i,j)+1
!              endif
!           elseif(-flux(k+1)+flux(k).gt.max(-qlatflux(k),0.))then
!                    infilflux(k,i,j) = infilflux(k,i,j) + max(-flux(k+1),0.)*1.e3
!                    infilcounter(k,i,j)=infilcounter(k,i,j)+1
!           endif
!         endif
!       enddo
!save infiltration
       do k=nzg,1,-1
         if(flux(k+1).lt.0.)then
            infilflux(k,i,j) = infilflux(k,i,j) + flux(k+1)*1.e3
         else
            upflux(k,i,j) = upflux(k,i,j) + flux(k+1)*1.e3
         endif

         infilfluxday(k,i,j) = infilfluxday(k,i,j) + flux(k+1)*1.e3
       enddo

!infiltration counter
       if(hour.eq.0)then
         do k=nzg,1,-1
           if(infilfluxday(k,i,j).lt.-0.01) infilcounter(k,i,j) = infilcounter(k,i,j) + 1
           infilfluxday(k,i,j)=0.
         enddo
       endif


!infiltration counter

!       do k=nzg,1,-1
!           if(flux(k+1).lt.-0.333e-5)infilcounter(k,i,j)=infilcounter(k,i,j)+1
!       enddo



!     do k=1,nzg
!       if(0.5*(flux(k)+flux(k+1)).lt.-1.e-6)then
!            if(pppendepth(i,j).gt.0.5*(slz(k)+slz(k+1)))pppendepth(i,j)=0.5*(slz(k)+slz(k+1))
!            exit
!       endif
!     enddo

     infilkstep=nzg+1
     pppendepthstep=0.
     flux(nzg+1)=-1.
     do k=nzg,0,-1
       if(k.le.nzg-2)then
!           if(pppendepthold(i,j).gt.slz(k+2)+0.5*dz(k+2))exit
           if(pppendepthold(i,j).ge.k+3)exit
       endif
!       if(flux(k+1).lt.-1.e-5)then
       if(flux(k+1).lt.-0.333e-5)then  !since the timestep was reduced from 3 to 1 h, change the threshold accordingly
           if(k.eq.0)then
              if(-flux(1).gt.-qlatflux(1).and.pppendepthstep.gt.slz(1))then
                        pppendepthstep=slz(1)
                        infilkstep=1
              endif
           elseif(-flux(k+1)+flux(k).gt.-qlatflux(k)+dsmoi(k).and.pppendepthstep.gt.slz(k+1))then
              pppendepthstep=slz(k+1)
              infilkstep=k+1
           endif
       endif
     enddo

     pppendepthold(i,j) = infilkstep

     if(pppendepth(i,j).gt.pppendepthstep)pppendepth(i,j)=pppendepthstep

     if(slz(max(infilkstep-1,1)).le.wtdold)wtdflux(i,j)=wtdflux(i,j)-flux(infilkstep)*1.e3
     if(infilk(i,j).gt.infilkstep)infilk(i,j)=infilkstep

!save downward flux




!if(i.eq.2761.and.j.eq.571)write(6,*)'smoi',(smoi(k,i,j),k=1,nzg)
!if(i.eq.2761.and.j.eq.571)write(6,*)'ncount',(ncount(k,i,j),k=1,nzg)

  ENDDO
ENDDO


end subroutine rootdepth

!     ******************************************************************

subroutine INTERCEPTION(minpprate,precip,lai,intercepstore,ppdrip,pet_i,et_i)

real :: minpprate,precip,lai,intercepstore,ppdrip,pet_i,et_i
real :: intercepmax,deficit

     intercepmax = 0.2 * lai
     deficit = intercepmax - intercepstore

     if( precip .gt. deficit ) then
          if(precip.lt.minpprate)then
             et_i = min ( intercepmax, pet_i)
          else
             et_i = 0.
          endif
          intercepstore = intercepmax - et_i
          ppdrip = precip - deficit
     else
          if(precip.lt.minpprate)then
             et_i = min ( intercepstore + precip, pet_i)
          else
             et_i = 0.
          endif
          intercepstore = intercepstore + precip - et_i
          ppdrip = 0.
     endif


end subroutine interception

!     ******************************************************************

subroutine EXTRACTION(i,j,nzg, slz, dz, deltat, soiltxt,wtd,smoi,smoiwtd &
                     ,delta,gamma,lambda,lai,ra_a,ra_c,rs_c_factor,R_a,R_s,petfactor_s,petfactor_c,pet_s &
                     , pet ,watdef,dsmoi,dsmoideep &
                     ,inactivedays,maxinactivedays,fieldcp,hhveg,fdepth,icefac)

real, parameter :: potleaf = -153. !now equal to wilting point
!real, parameter :: potleaf = -102.!-204.  !for now constant
!real, parameter :: potleaf = -204.  !for now constant
real, parameter :: potwilt=-153. !matric potential at wilting point
real, parameter :: potfc=-3.366 !matric potential at field capacity
integer :: i,j,nzg,nsoil,nsoil1,k,alarm,iwtd,kwtd,maxinactivedays,kroot
real, dimension(nzg,nstyp) :: fieldcp
integer :: soiltxt(2)
integer, dimension(0:nzg+1) :: inactivedays
real, dimension(nzg+1) :: slz
integer,dimension(nzg) :: rootmask
integer*1,dimension(nzg) :: icefac
real, dimension(nzg) :: smoi,dz,dz2,vctr4,rootactivity,easy,dsmoi,maxwat
real :: deltat,pet,transpwater,totwater,watdef,extract,kf,pot,toteasy,easydeep,dz3
real :: wtd,smoiwtd,dzwtd,rootactivitydeep,dsmoideep,smoimin,maxeasy,soilfactor,fieldc,hveg,hhveg,zz,fdepth,psisat,smoisat,smoifc
real :: delta,gamma,lambda,lai,ra_a,ra_c,rs_s,rs_c_factor,rs_c,R_a,R_s,petfactor_s,petfactor_c,pet_s,fswp,rootsmoi,rootfc,R_c,C_c,C_s

    hveg = 2.*hhveg/3.
!initialize
    easy = 0.
    easydeep = 0.
    dzwtd = 0.
    rootmask = 0
    dz2=dz
    dz3=0.

!take water from layers

!    transpwater = pet * 1.e-3

!calculate where the water table is

     do k=1,nzg
     if(wtd.lt.slz(k))exit
     enddo
     iwtd=k
     kwtd=k-1

     if(kwtd.ge.1.and.kwtd.lt.nzg)dz2(kwtd)=slz(iwtd)-wtd

!calculate lowest layer of the root zone

     do k=1,nzg
      if(inactivedays(k).le.maxinactivedays)exit
     enddo
     kroot=k-1


    do k=max(kwtd,kroot,1),nzg


!check if this layer has roots or can have roots growing from the layer above
!         if(inactivedays(k).gt.maxinactivedays.and.inactivedays(k+1).gt.maxinactivedays)cycle
         if(inactivedays(k).le.maxinactivedays)rootmask(k)=1


         vctr4(k) =  0.5 * (slz(k) + slz(k+1))

         if(slz(k).lt.-0.30)then
               nsoil=soiltxt(1)
         else
               nsoil=soiltxt(2)
         endif

!calculte the easiness function for extraction for each layer

!      if(abs(slmsts(nsoil)-smoi(k)).lt.1.e-6.and.k.ne.nzg)then
!           easy(k)=0.
!      if(smoi(k).le.slwilt(nsoil))then
!          easy(k)=0.
!      else

! calculate moisture potential
         smoisat = slmsts(nsoil)*max(min(exp((vctr4(k)+1.5)/fdepth),1.),0.1)
         psisat = slpots(nsoil)*min(max(exp(-(vctr4(k)+1.5)/fdepth),1.),10.)
         pot = psisat  * (smoisat / smoi(k)) ** slbs(nsoil)

            if(icefac(k).eq.0)then
                 soilfactor = 1.
            else
                 soilfactor = 0.
            endif

         easy(k)= max(-( potleaf - pot )*soilfactor / ( hveg-vctr4(k) ) , 0.) 

!      endif

    enddo



      dsmoi = 0.
      dsmoideep = 0.
      watdef = 0.

!eliminate small root activity
!       where(easy.lt.0.01)easy=0.
!       if(easydeep.lt.0.01)easydeep=0.

!to grow roots anew, the layer has to be easiest to get water from than the
!current active layers with roots

         maxeasy =  maxval(easy,rootmask==1)

!eliminate small root activity
       where(easy.lt.0.001*maxeasy)easy=0.



         do k=max(kroot,1),nzg
             if(inactivedays(k).gt.maxinactivedays.and.easy(k).lt.maxeasy)easy(k)=0.
         enddo


         toteasy=sum(easy*dz2) 
         if(toteasy.eq.0.)then
!              watdef = transpwater
!              return
!         endif
             rootactivity=0.
          else
             rootactivity = min ( max(  ( easy*dz2 ) /  toteasy  , 0. ), 1. )
          endif

!eliminate small root activity
!         where(rootactivity.lt.0.01.and.rootmask==1)easy=0.
!         if(rootactivitydeep.lt.0.01)easydeep=0.
!recalculate
!         toteasy=sum(easy*dz) + easydeep*dzwtd
!         rootactivity = min ( max(  ( easy*dz ) /  toteasy  , 0. ), 1. )
!         rootactivitydeep = min ( max(  ( easydeep*dzwtd ) /  toteasy  , 0. ), 1. )


         do k=1,nzg
           if(easy(k).eq.0.)then
                   inactivedays(k)=inactivedays(k)+1
           else
                   inactivedays(k)=0
           endif
         enddo

         inactivedays=min(inactivedays,maxinactivedays+1)



!         if(i.eq.89.and.j.eq.193)write(6,*)(rootactivity(k),k=1,nzg),sum(rootactivity)
!         if(i.eq.89.and.j.eq.193)write(6,*)(easy(k),k=1,nzg),sum(easy*dz),toteasy

rootsmoi=0.
rootfc=0.

    do k=max(kwtd,1),nzg

         if(slz(k).lt.-0.30)then
               nsoil=soiltxt(1)
         else
               nsoil=soiltxt(2)
         endif

         smoisat = slmsts(nsoil)*max(min(exp((vctr4(k)+1.5)/fdepth),1.),0.1)
         psisat = slpots(nsoil)*min(max(exp(-(vctr4(k)+1.5)/fdepth),1.),10.)
         smoimin = smoisat * ( psisat / potwilt )**( 1. / slbs(nsoil) )
         smoifc = smoisat * ( psisat / potfc )**( 1. / slbs(nsoil) )
         
!         smoimin = max(smoimin,slwilt(nsoil))
         maxwat(k) = max( ( smoi(k) - smoimin ) * dz(k) , 0. )  !max water than can be taken from a layer

         rootsmoi = rootsmoi + max(rootactivity(k)*(smoi(k)-smoimin),0.)
         rootfc = rootfc + max(rootactivity(k)*(smoifc-smoimin),0.)

     enddo


     if(rootsmoi.le.0)then
           fswp=0.
     elseif(rootsmoi/rootfc.le.1)then
           fswp=rootsmoi/rootfc
     else
           fswp=1.
     endif

      
      if(fswp.eq.0.)then
         rs_c=5000.
      else
         rs_c = min( rs_c_factor / fswp , 5000. )
      endif

      nsoil=soiltxt(2)
      rs_s = 33.5 + 3.5*(slmsts(nsoil)/smoi(nzg))**2.38

      R_c = (delta + gamma) * ra_c + gamma*rs_c 
      R_s = R_s + gamma*rs_s

      C_c = 1. / ( 1. + R_a*R_c / (R_s * (R_c+R_a) ) )
      C_s = 1. / ( 1. + R_a*R_s / (R_c * (R_s+R_a) ) )


      if(lai.lt.0.001)then
             C_c=0.
!             C_s=1.
      endif

!calculate transpiration and soil evaporation. Both depend on stomatal
!resistence, thats why the final step has to be computed here
pet = C_c * petfactor_c / (delta + gamma*(1.+rs_c/(ra_a+ra_c)) )
pet = max( deltat * pet / lambda, 0.)

pet_s = C_s * petfactor_s / (delta + gamma*(1.+rs_s/(ra_a+ra_c)) )
pet_s = max( deltat * pet_s / lambda , 0.)


    transpwater = pet * 1.e-3


         if(toteasy.eq.0.)then
              watdef = transpwater
              return
         endif


    do k=max(kwtd,1),nzg

!calculate hyd. conductivity
!         kf =   slcons(nsoil) * (smoi(k)  / slmsts(nsoil)) ** (2. * slbs(nsoil) + 3.)
!         maxwat = min( maxwat , kf*deltat )

!extract water
         extract = max(rootactivity(k)*transpwater,0.)   !water to be extracted from this layer this timestep
         
         if(extract.le.maxwat(k))then
                      dsmoi(k) =  extract
         else
                      dsmoi(k) =  maxwat(k)
                      watdef = watdef + (extract-maxwat(k))
         endif
                  
     enddo





     dsmoi=max(dsmoi,0.)

if(abs(watdef-transpwater).gt.1.e9)write(6,*)'algo no esta bien',i,j,transpwater*1.e3,watdef*1.e3

!now total rootactiviy is dsmoi/totwater normalized by soil layer depth, return dsmoi (total water taken from each layer) to do calculation later and update soil moisture

!       smoi = smoi - dsmoi/dz


end subroutine extraction

!     ******************************************************************

subroutine POTEVAP_Priestly_Taylor(i,j,tempk,rad,presshp,pet)

integer :: i,j
real, parameter :: cp = 1013. * 1e-6
real :: tempk, tempc, rad, presskp,presshp, pet
real :: alpha,delta,gamma,lambda

tempc = tempk - 273.15     !C
presskp = presshp*0.1       !kPa
rad = rad * 24. * 3600. *1.e-6 !MJ/day/m2

alpha = 1.26
delta = 0.2 * ( 0.00738 * tempc + 0.8072 )**7. - 0.000116
lambda =  2.501 - 0.002361 * tempc
gamma = (cp * presskp) / (0.622*lambda)

pet = alpha * rad * delta / ( delta + gamma ) 
pet = pet / lambda


end subroutine potevap_priestly_taylor

!     ******************************************************************
    
subroutine POTEVAP_Penman_Monteith(i,j,tempk,rad,rshort,press,qair,wind,lai,veg,hveg,pet)
real, parameter :: cp = 1013. , vk=0.41 ,Rd=287.
integer :: i,j
real :: tempk,rad,rshort,press,qair,wind,lai,veg,pet
real :: zm,hveg,hdisp,z0m,zh,z0h,hhveg
real :: slai,frad,fswp,fvpd,g_d,ra,rs
real :: delta,pressesat,pressvap,lambda,gamma,tempc,vpd,dens
real, dimension(30) :: rl
real, dimension(0:30) :: zdis
data rl/150.,150.,500.,500.,175.,240.,110.,100.,250.,150. &
          ,80. ,225.,225.,250.,180.,180.,240.,500.,240.,500. &
          ,175.,250.,250.,175.,225.,150.,110.,180.,250.,250./
data zdis/0.1,0.1,0.1,15.,20.,15.,20.,.2,1.,.1,.5,.1,1.,1.,20.,.7,.7,1. &
         ,10.2,20.7,9.2,7.2,6.5,7.4,3.6,1.4,.2,.2,.2,.2,1.1/

tempc = tempk - 273.15
pressesat = 610.8*exp(17.27*tempc/(tempc+237.3)) !Pa
!pressvap = pressesat*rh !Pa
pressvap = qair*press / (0.622+qair) !Pa
!delta = 4098. * 610.8 * exp( 17.27*tempc / (tempc+237.3) )  / (tempc+237.3)**2. !Pa/K
!pressvap = pressesat*rh !Pa
delta = 4098. * pressesat / (tempc+237.3)**2. !Pa/K
vpd = pressesat-pressvap
lambda =  (2.501 - 0.002361 * tempc)*1.e6 !J/kg
gamma = (cp * press) / (0.622*lambda)
dens = press / (Rd * tempk*(1.+0.608*qair))

if(i==300.and.j.eq.300)write(6,*)'mirar 1 forcing',tempk,rad,rshort,press,qair,wind,lai,veg,hveg
if(i==3.and.j.eq.3)write(6,*)'mirar 2 forcing',tempk,rad,rshort,press,qair,wind,lai,veg,hveg

!hveg=min(10.,hhveg)
!hveg=zdis(nint(veg))
!aerodynamic resistance
      zm = max(10.,hveg)
!      hdisp = 0.7*hveg
!      if (hveg.lt.10.)then
!             zm=10.
!      else
!             zm=10+hdisp
!      endif
      z0m = 0.1*hveg
      zh = max(2.,hveg)
!      if (hveg.lt.2.)then
!             zh=2.
!      else
!             zh=2.+hveg
!      endif

      z0h = 0.1*z0m

      ra = log( (zm-hdisp)/z0m ) * log( (zh-hdisp)/z0h ) / (vk**2. * wind)

!bulk surface resistance
      frad = min(1.,(0.004*rshort+0.05)/(0.81*(1.+0.004*rshort)))
      fswp = 1.
      
      if(hdisp.gt.2.)then
            g_d=0.0003
      else
            g_d=0.
      endif

      fvpd = exp(-g_d * vpd)

      slai = 0.5 * lai


      if( slai*frad*fswp*fvpd .eq. 0.) then
            rs = 5000.
      else
            rs=min(rl(nint(veg))/(slai*frad*fswp*fvpd),5000.)
      endif

!pet

pet = ( delta*rad + dens*cp*vpd/ra ) / (delta + gamma*(1.+rs/ra))
pet = 3.*3600.*pet/lambda

if(i==300.and.j.eq.300)write(6,*)'mirar 1 results',delta,pressesat,pressvap,lambda,gamma,dens,ra,rs,pet
if(i==3.and.j.eq.3)write(6,*)'mirar 2 results',delta,pressesat,pressvap,lambda,gamma,dens,ra,rs,pet

end subroutine potevap_penman_monteith

!     ******************************************************************

subroutine POTEVAP_Shutteworth_Wallace(i,j,deltat,tempk,rad,rshort,press,qair,wind,lai,veg,hhveg  &
                                      ,delta,gamma,lambda,ra_a,ra_c,rs_c,R_a,R_s &
                                      ,pet_s,pet_c,pet_w,pet_i,floodflag)
real, parameter :: cp = 1013. , vk=0.41 ,Rd=287.
integer :: i,j,floodflag
real :: deltat,tempk,rad,rshort,press,qair,wind,lai,veg,pet
real :: zm,hveg,z0m,zh,z0h,hhveg,z0g
real :: slai,frad,fswp,fvpd,g_d,ra,rs
real :: smoi,smoiwp,smoifc
real :: delta,pressesat,pressvap,lambda,gamma,tempc,vpd,dens
real :: Rn_s,za,z0c,c_d,d0,ustar,K_h,n,dp,Z0,ra_a,ra_s,uc,wleaf,rb,ra_c,rs_c,rs_s
real :: R_a,R_c,R_s,C_c,C_s,pet_c,pet_s,pet_w,pet_i
real, dimension(30) :: rl
real, dimension(0:30) :: zdis,z0gr,wmax
real, dimension(2,0:30) :: bioparms
data rl/150.,150.,500.,500.,175.,240.,110.,100.,250.,150. &
          ,80. ,225.,225.,250.,180.,180.,240.,500.,240.,500. &
          ,175.,250.,250.,175.,225.,150.,110.,180.,250.,250./
data zdis/0.1,0.1,0.1,15.,20.,15.,20.,.2,1.,.1,.5,.1,1.,1.,20.,.7,.7,1. &
         ,10.2,20.7,9.2,7.2,6.5,7.4,3.6,1.4,.2,.2,.2,.2,1.1/
data bioparms/ &
 .001,   0.    & !  0  Ocean
,.001,   0.    & !  1  Lakes, rivers, streams (inland water)
,.001,   0.    & !  2  Ice cap/glacier
,.02,    .001  & !  3  Evergreen needleleaf tree
,.02,   0.001  & !  4  Deciduous needleleaf tree
,.02,   0.08   & !  5  Deciduous broadleaf tree
,.02,   0.05   & !  6  Evergreen broadleaf tree
,.01,   0.01   & !  7  Short grass
,.01,   0.01   & !  8  Tall grass
,.001,  0.01   & !  9  Desert
,.01,   0.01   & ! 10  Semi-desert
,.01,   0.01   & ! 11  Tundra
,.02,   0.01   & ! 12  Evergreen shrub
,.02,   0.01   & ! 13  Deciduous shrub
,.02,   0.04   & ! 14  Mixed woodland
,.005,  0.01   & ! 15  Crop/mixed farming
,.005,  0.01   & ! 16  Irrigated crop
,.01,   0.01   & ! 17  Bog or marsh
!LDAS LSPs, but emissivity based on above
,.01,    .001  & ! 18  Evergreen needleleaf forest
,.02,    .05   & ! 19  Evergreen broadleaf forest
,.02,    .001  & ! 20  Deciduous needleleaf forest
,.02,    .08   & ! 21  Deciduous broadleaf forest
,.01,    .01   & ! 22  Mixed cover
,.02,    .04   & ! 23  Woodland
,.02,    .01   & ! 24  Wooded grassland
,.02,    .01   & ! 25  Closed shrubland
,.02,    .01   & ! 26  Open shrubland
,.01,    .01   & ! 27  Grassland
,.005,   .01   & ! 28  Cropland
,.001,   .01   & ! 29  Bare ground
,.02,    0./     ! 30  Urban and built up


z0gr(:) = bioparms(1,:)
wmax(:) = bioparms(2,:)

tempc = tempk - 273.15
pressesat = 610.8*exp(17.27*tempc/(tempc+237.3)) !Pa
!pressvap = pressesat*rh !Pa
pressvap = qair*press / (0.622+qair) !Pa
!delta = 4098. * 610.8 * exp( 17.27*tempc / (tempc+237.3) )  / (tempc+237.3)**2.
!!Pa/K
!pressvap = pressesat*rh !Pa
delta = 4098. * pressesat / (tempc+237.3)**2. !Pa/K
vpd = pressesat-pressvap
lambda =  (2.501 - 0.002361 * tempc)*1.e6 !J/kg
gamma = (cp * press) / (0.622*lambda)
dens = press / (Rd * tempk*(1.+0.608*qair))

!make sure that hveg is not zero
hveg=max(hhveg,0.1)

IF(nint(veg).le.1)then

pet_w = ( delta * rad + gamma * 6.43 * ( 1. + 0.536 * wind) * vpd / (24.*3600.) ) / ( delta+gamma )
pet_w = max( deltat * pet_w / lambda, 0.)

pet_s = 0.

pet_c = 0.

pet_i = 0.

ELSE

pet_w = 0.

!!Radiation

!net radiation on the ground

    Rn_s = rad * exp(-0.5*lai)

!!!Resistances
!ra_a aerodynamic resistance from canopy to reference height

    za = hveg + 2. !ref. height

!roughness for a closed canopy z0c

if(hveg.le.1.)then
    z0c = 0.13 * hveg
elseif(hveg.gt.1..and.hveg.lt.10.)then
    z0c = 0.139*hveg - 0.009*hveg**2.
else
    z0c = 0.05 * hveg
endif

!mean drag coefficient for individual leafs

if(hveg.eq.0.)then
    c_d = 1.4e-3
else
    c_d = ( -1. + exp( 0.909 - 3.03*z0c/hveg ) )**4. / 4.
endif

!zero plane displacement height d0

if(lai.ge.4.)then
    d0 = max( hveg - z0c/0.3 , 0.)
else
    d0 = 1.1 * hveg * log( 1. + (c_d*lai)**0.25 )
endif

if(d0.gt.hveg)write(6,*)'big problem!',d0,hveg,i,j

!reference height

!   za = 10. + d0

!ground roughness length

  if(floodflag.eq.0)then
         z0g = z0gr(nint(veg))
  else
         z0g = z0gr(1)
  endif

!roughness lengtt of canopy z0

    z0 = min( 0.3*(hveg-d0) , z0g + 0.3*hveg*(c_d*lai)**0.5 )

    z0 = max(z0,z0g)

!friction  velocity ustar

!    ustar = vk * wind / log( (za-d0)/z0 )
    ustar = vk * wind / log( 10./z0 )

!Eddy diffusion coefficient at the top of the canopy

    K_h = vk * ustar * (hveg - d0 )

!eddy diff. decay constant for vegetation, n

if(hveg.le.1.)then
    n = 2.5
elseif(hveg.gt.1..and.hveg.lt.10.)then
    n = 2.306 + 0.194*hveg
else
    n = 4.25
endif

!preferred roughness length Z0
    Z0 = 0.13 * hveg

!preferred zero plane displacement dp
  
    dp = 0.63 * hveg

!and finally

    ra_a = log( (za-d0)/(hveg-d0) ) / (vk*ustar) &
           + hveg * ( exp( n * ( 1. - (Z0+dp)/hveg ) ) -1. ) / (n*K_h)


!!ra_s aerodynamic resistance from soil to canopy

    ra_s = hveg*exp(n) * ( exp(-n*z0g/hveg) - exp( -n*(Z0+dp) / hveg ) ) / (n*K_h)


!!Bulk boundary layer resistance of canopy, ra_c

!uc, wind at canopy top

    uc = ustar * log( (hveg-d0)/z0 ) / vk


!wleaf

    select case(nint(veg))
       case(4,5,13,20,21)
          wleaf = wmax(nint(veg)) * (1. - exp(-0.6*lai))
       case default
          wleaf = wmax(nint(veg))
    end select

!rb

    rb = 100. * (wleaf/uc)**0.5 / ( ( 1. - exp (-n/2.) ) * n )

!
  if(lai.gt.0.1)then
    ra_c = rb * 0.5 /lai
  else
    ra_c = 0.
  endif


!!Bulk stomatal resistance of canopy rs_c

      frad = min(1.,(0.004*rshort+0.05)/(0.81*(1.+0.004*rshort)))
!this is how it was in the runs for PNAS
      fswp = 1.
      

      if(d0.gt.2.)then
            g_d=0.0003
      else
            g_d=0.
      endif

      fvpd = exp(-g_d * vpd)

      slai = 0.5 * lai


      if( slai*frad*fswp*fvpd .eq. 0.) then
            rs_c = 5000.
      else
            rs_c = min(rl(nint(veg))/(slai*frad*fswp*fvpd),5000.)
      endif



!!Surface resistance of substrate soil rs_s
!now in extraction
!     if(floodflag.eq.0)then
!         rs_s = 500.
!     else
!         rs_s = 0.
!     endif

!!!!!!!!!!!!!!!!

      R_a = (delta + gamma) * ra_a
!      R_c = (delta + gamma) * ra_c + gamma*rs_c in the call
!      R_s = (delta + gamma) * ra_s + gamma*rs_s in the call

!      C_c = 1. / ( 1. + R_a*R_c / (R_s * (R_c+R_a) ) )
!      C_s = 1. / ( 1. + R_a*R_s / (R_c * (R_s+R_a) ) )

!      if(lai.lt.0.001)then
!             C_c=0.
!             C_s=1.
!      endif

!!PET

!pet_c = C_c * ( delta*rad + ( dens*cp*vpd - delta*ra_c*Rn_s ) / (ra_a+ra_c) ) / (delta + gamma*(1.+rs_c/(ra_a+ra_c)) )
!pet_c = max( deltat * pet_c / lambda , 0.)
pet_c = ( delta*rad + ( dens*cp*vpd - delta*ra_c*Rn_s ) / (ra_a+ra_c) )

!pet_s = C_s * ( delta*rad + ( dens*cp*vpd - delta*ra_s*(rad-Rn_s) ) / (ra_a+ra_s) ) / (delta + gamma*(1.+rs_s/(ra_a+ra_c)) )
!pet_s = max( deltat * pet_s / lambda , 0.)
!pet_s = ( delta*rad + ( dens*cp*vpd - delta*ra_s*(rad-Rn_s) ) / (ra_a+ra_s) ) / (delta + gamma*(1.+rs_s/(ra_a+ra_c)) )
pet_s = ( delta*rad + ( dens*cp*vpd - delta*ra_s*(rad-Rn_s) ) / (ra_a+ra_s) )


!for PET from interception loss rs_c=rs_s = 0.
      R_c = (delta + gamma) * ra_c 
      R_s = (delta + gamma) * ra_s
      C_c = 1. / ( 1. + R_a*R_c / (R_s * (R_c+R_a) ) )
      if(lai.lt.0.001)C_c=0.

pet_i = C_c * ( delta*rad + ( dens*cp*vpd - delta*ra_c*Rn_s ) / (ra_a+ra_c) ) / (delta + gamma)
pet_i = max( deltat * pet_i / lambda , 0.)

pet_w = 0.


if((pet_c.ne.pet_c).or.(pet_s.ne.pet_s).or.(pet_i.ne.pet_i))then
write(6,*)'something wrong with pet',pet_c,pet_s,pet_i,ra_a,ra_c,rs_c,ra_s,rs_s
write(6,*)'forcings',i,j,tempk,rad,rshort,press,qair,wind,lai,veg,hhveg
endif

ENDIF

!pet = 3.*3600.* ( C_c*pet_c + C_s*pet_s + pet_w ) / lambda





end subroutine POTEVAP_Shutteworth_Wallace
!     ******************************************************************

subroutine INITIALIZESOILDEPTHCLM(nzg,slz,dz)

integer :: nzg,k,kk
real, dimension(nzg+1) :: slz,slz2
real, dimension(nzg) :: dz,dz2,vctr4


   do k=1,nzg
      vctr4(k) = 0.025 * (exp( 0.5*(float(k)-0.5) ) -1.)
   enddo

!write(6,*)'soil nodes',(-vctr4(k),k=nzg,1,-1)

   do k=2,nzg-1
      dz2(k)=0.5*(vctr4(k+1)-vctr4(k-1))
   enddo
      dz2(1)=0.5*(vctr4(1)+vctr4(2))
      dz2(nzg)=vctr4(nzg)-vctr4(nzg-1)


   do k=1,nzg
      slz2(k)=0.5*(vctr4(k)+vctr4(k+1))
   enddo

      slz2(nzg)=vctr4(nzg)+0.5*dz2(nzg)

   do k=1,nzg
      kk=nzg-k+1
      slz(k)=-slz2(kk)
      dz(k)=dz2(kk)
   enddo

      slz(nzg+1)=0.



end subroutine initializesoildepthclm

!     ******************************************************************

subroutine INITIALIZESOILDEPTH(nzg,slz,dz)

integer :: nzg,k,kk
real, dimension(nzg+1) :: slz,slz2
real, dimension(nzg) :: dz,vctr4
real, dimension(40) :: dz2
data dz2/.1,.1,.1,.1,.1,.2,.2,.2,.2,.2,.3,.3,.3,.3,.4,.4 &
       ,.4,.5,.5,.6,.7,.7,.8,.9,1.,1.,1.2,1.2,1.5,1.5,2.,2. &
       ,3.,6.,11.,20.,50.,100.,250.,540./

!5.,10.,25.,50.,100.,200.,500.,1000./

   slz(nzg+1) = 0.
   do k=nzg,1,-1
        dz(k)=dz2(nzg-k+1)
        slz(k)=slz(k+1)-dz(k)
   enddo

end subroutine initializesoildepth


!******************************************************************************
subroutine SOILFLUXES(i,j,nzg,freedrain,dtll,slz,dz,soiltxt,smoiwtd,transp,transpdeep  &
                      ,smoi,wtd,rech,deeprech,precip,pet_s,et_s,runoff,flux,fdepth,qlat &
                      ,qlatflux,qrf,qrfcorrect,flood,icefactor &
                      ,smoieq,o18,precipo18,tempsfc,qlato18,transpo18)!pppendepth)
implicit none

integer :: nzg,freedrain,nsoil,nsoil1,k,iwtd,kwtd,i,j
real, dimension(nzg+1) :: slz
real, dimension(nzg) :: dz
real, dimension(nzg) ::vctr2,vctr4,vctr5,vctr6
real, dimension(nzg) :: transp,smoi,kfmid,diffmid &
                        ,aa,bb,cc,rr,smoieq,o18,o18dz
real, dimension(nzg) :: smoiold,o18ratio
real*8, dimension(nzg+1) :: vt3di,o18flux,gravflux,capflux
real, dimension(nzg+1) :: flux
real , dimension(0:nzg+1) :: qlatflux
integer, dimension(2) :: soiltxt
integer*1, dimension(nzg) :: icefactor
real :: precip,runoff,pet_s,et_s,transpdeep,pppendepth,precipo18,tempsfc,qgwo18
real :: wgpmid,kfup,kfdw,hydcon,newwgp,smoiwtd,rech,deeprech,wtd,deeptemp &
     ,fracliqwtd,wmid,wtdold,dzup,vt3dbdw,vt3dcdw,dtll,smoibot,icefac,ddw,dup &
     ,smoisat,psisat,smoicp,fdepth,qlat,qlato18,qrf,qrfcorrect,qgw,flood,transpo18
real*8 :: alpha,o18evap,dsmoi,transptot,qlatlayer,qrflayer,o18frac,o18out,o18tot,fluxdiff

         do k=1,nzg
            vctr2(k) = 1. / dz(k)
            vctr4(k) = 0.5 * (slz(k) + slz(k+1))
         enddo
         do k = 2,nzg
            vctr5(k) = vctr4(k) - vctr4(k-1)
            vctr6(k) = 1. / vctr5(k)
         enddo


         kfmid = 0.
         diffmid = 0.

         vt3di = 0.
         gravflux = 0.
         capflux = 0.
   
         rech = 0. 
         runoff = 0.

!o18 ratio
         o18ratio = o18 / smoi  
         smoiold = smoi 

         qgw = qlat - qrf

!top boundary condition, infiltration + potential et from soil
         nsoil=soiltxt(1)
         smoicp = soilcp(nsoil)
         if(smoi(nzg).le.smoicp)pet_s=0.
         vt3di(nzg+1)= (-precip + pet_s ) * 1.e-3 - flood

         if(-vt3di(nzg+1).gt.slcons(nsoil)*dtll)then
             runoff = -vt3di(nzg+1)-slcons(nsoil)*dtll
             vt3di(nzg+1) = -slcons(nsoil)*dtll
         endif
         
!         smoisat = slmsts(nsoil)
!         dsmoi = max((smoisat-smoi(nzg))*dz(nzg)+transp(nzg),0.)
!         if(-vt3di(nzg+1).gt.dsmoi)then
!             runoff = -vt3di(nzg+1)-dsmoi
!             vt3di(nzg+1)=-dsmoi
!         endif

if(freedrain.eq.0)then
     do k=1,nzg
     if(wtd.lt.slz(k))exit
     enddo
     iwtd=k
else
     iwtd=0
endif


!k=max(iwtd-1,1)
!qlatflux(k)=qlatflux(k)+qgw
   
!         do k = 2,nzg

         do k=max(iwtd-1,2),nzg


!gmmdiffusivity and conductivity at the interlayers

            wgpmid=smoi(k)+(smoi(k)-smoi(k-1))*(slz(k)-vctr4(k))*vctr6(k)

            if(slz(k).lt.-0.30)then
                  nsoil=soiltxt(1)
            else
                  nsoil=soiltxt(2)
            endif

            hydcon = slcons(nsoil)*max(min(exp((slz(k)+1.5)/fdepth),1.),0.1)
            smoisat = slmsts(nsoil)*max(min(exp((slz(k)+1.5)/fdepth),1.),0.1)
            psisat = slpots(nsoil)*min(max(exp(-(slz(k)+1.5)/fdepth),1.),10.)

            wgpmid=min(wgpmid,smoisat)
!            icefac=fracliq(k)** (2. * slbs(nsoil) + 3.)
!            icefac=1.
            if(icefactor(k).eq.0)then
                icefac=1.
            else
                icefac=0.
            endif

            kfmid(k) =   icefac * hydcon  &
               * (wgpmid  / smoisat ) ** (2. * slbs(nsoil) + 3.)
            diffmid(k) =-icefac * (hydcon*psisat*slbs(nsoil)/smoisat)  &
                       * (wgpmid/smoisat) **(slbs(nsoil)+2.)


!write(6,*)k,diffmid(k),kfdw,kfup,ddw,dup,smoi(k),smoi(k-1)

         enddo


!calculate tridiagonal matrix elements

!       do k=2,nzg-1
!         do k=max(iwtd-2,2),nzg
         do k=max(iwtd,3),nzg

            aa(k) = diffmid(k)*vctr6(k)
            cc(k) = diffmid(k+1)*vctr6(k+1)
            bb(k) = -( aa(k) + cc(k) + dz(k)/dtll )
            rr(k) = -smoi(k)*dz(k)/dtll -kfmid(k+1) +kfmid(k) + transp(k)/dtll
!            if(k.eq.iwtd-1)rr(k) = rr(k) - qgw/dtll

        enddo


!boundary conditions

!top boundary

         if(iwtd-1.eq.nzg)then
            aa(nzg) = 0.
            cc(nzg) = 0.
            bb(nzg) = - dz(nzg)/dtll 
            rr(nzg) = vt3di(nzg+1)/dtll -smoi(nzg)*dz(nzg)/dtll + transp(k)/dtll + min( kfmid(nzg)+ diffmid(nzg)*vctr6(nzg)*(smoi(nzg)-smoi(nzg-1)) , 0. )
         else
            aa(nzg) = diffmid(nzg)*vctr6(nzg)
            cc(nzg) = 0.
            bb(nzg) = -aa(nzg) -dz(nzg)/dtll
            rr(nzg) = vt3di(nzg+1)/dtll -smoi(nzg)*dz(nzg)/dtll +kfmid(nzg) + transp(nzg)/dtll
!            if(iwtd-1.eq.nzg)rr(nzg) = rr(nzg) - qgw/dtll
         endif

!now bottom boundary condition

IF(freedrain.ne.1)then

   if(iwtd.le.2)then
            aa(1) = 0.
            cc(1) = diffmid(2)*vctr6(2)
            bb(1) = -( cc(1) + dz(1)/dtll )
            rr(1) = -smoi(1)*dz(1)/dtll -kfmid(2) + transp(1)/dtll
!            if(iwtd.le.2)rr(1) = rr(1) - qgw/dtll
         
            k=2
            aa(k) = diffmid(k)*vctr6(k)
            cc(k) = diffmid(k+1)*vctr6(k+1)
            bb(k) = -( aa(k) + cc(k) + dz(k)/dtll )
            rr(k) = -smoi(k)*dz(k)/dtll -kfmid(k+1) +kfmid(k) + transp(k)/dtll
    else
         do k=1,iwtd-3
            aa(k)=0.
            cc(k)=0.
            bb(k)=1.
            rr(k)=smoi(k)
         enddo

         k=iwtd-1 ! layer where the water table is
            aa(k) = 0.
            cc(k) = diffmid(k+1)*vctr6(k+1)
            bb(k) = -( cc(k) + dz(k)/dtll )
            rr(k) = -smoi(k)*dz(k)/dtll -kfmid(k+1) + transp(k)/dtll + min( kfmid(k)+ diffmid(k)*vctr6(k)*(smoi(k)-smoi(k-1)) , 0. )

         k=iwtd-2
            aa(k) = 0.
            cc(k) = 0.
            bb(k) = -dz(k)/dtll
            rr(k) = -smoi(k)*dz(k)/dtll + max( -kfmid(k+1)- diffmid(k+1)*vctr6(k+1)*(smoi(k+1)-smoi(k)) , 0. ) 
    endif


ELSE

!gmmgravitational drainage at the bottom
            nsoil=soiltxt(1)

            hydcon = slcons(nsoil)*max(min(exp((slz(1)+1.5)/fdepth),1.),0.1)
            smoisat = slmsts(nsoil)*max(min(exp((slz(1)+1.5)/fdepth),1.),0.1)

            kfmid(1) =   hydcon  &
               * (smoi(1)  / smoisat) ** (2. * slbs(nsoil) + 3.)

            aa(1) = 0.
            cc(1) = diffmid(2)*vctr6(2)
            bb(1) = -( cc(1) + dz(1)/dtll )
            rr(1) = -smoi(1)*dz(1)/dtll -kfmid(2) + kfmid(1) + transp(1)/dtll

ENDIF



!solve tridiagonal system and update smoi

            call tridag(aa,bb,cc,rr,smoi,nzg)


!calculate the fluxes

            do k=max(iwtd,3),nzg
                gravflux(k)=-kfmid(k)*dtll
                capflux(k)=-aa(k)*(smoi(k)-smoi(k-1))*dtll
                vt3di(k)=capflux(k)+gravflux(k)
!                if(k.le.iwtd-1)vt3di(k)=max(vt3di(k),0.)
            enddo
           if(iwtd.le.2)then
                 capflux(1) = 0.
                 gravflux(1) = 0.
                 vt3di(1) = 0.
                 gravflux(2)=-kfmid(2)*dtll
                 capflux(2)=-aa(2)*(smoi(2)-smoi(1))*dtll
                 vt3di(2)=capflux(2)+gravflux(2)
           else
                 do k=1,iwtd-2
                   capflux(k)=0.
                   gravflux(k)=0.
                   vt3di(k)=0.
                 enddo

                 k=iwtd-1
                 gravflux(k)=-kfmid(k)*dtll
                 capflux(k)=-diffmid(k)*vctr6(k)*(smoiold(k)-smoiold(k-1))*dtll
                 if(capflux(k).gt.-gravflux(k))then
                    vt3di(k) = capflux(k)+gravflux(k)
                 elseif(capflux(k).gt.0.)then
                    gravflux(k)=-capflux(k)
                    vt3di(k)=0.
                 else
                    capflux(k)=0.
                    gravflux(k)=0.
                    vt3di(k)=0.
                 endif

           endif

            if(freedrain.eq.0)then
                        vt3di(1)=0.
            else
                vt3di(1)=-kfmid(1)*dtll
            endif

smoi=smoiold
!recalculate soil moisture
     do k=1,nzg
          smoiold(k) = smoiold(k) + (vt3di(k) - vt3di(k+1) - transp(k)) * vctr2(k)
!          if(k.eq.iwtd-1)then
!                  smoiold(k) = smoiold(k) + qgw * vctr2(k)
!          endif
     enddo


!if(i.eq.25.and.j.eq.30)write(6,*)'fluxes antes',(vt3di(k),k=1,nzg)
!if(i.eq.25.and.j.eq.30)write(6,*)'capillarity',(-aa(k)*(smoi(k)-smoi(k-1)),k=2,nzg)
!if(i.eq.25.and.j.eq.30)write(6,*)'drainage',(-kfmid(k)*dtll,k=2,nzg)

! now check that soil moisture values are within bounds (slmsts and soilcp)
! if not, correct fluxes



        do k=1,nzg

            if(slz(k).lt.-0.30)then
                  nsoil=soiltxt(1)
            else
                  nsoil=soiltxt(2)
            endif

            smoisat = slmsts(nsoil)*max(min(exp((vctr4(k)+1.5)/fdepth),1.),0.1)

!if(i.eq.69.and.j.eq.34)write(6,*)'soilflux',k,smoi(k),smoiold(k),smoisat,vt3di(k+1),transp(k),iwtd-1,qgw,qlat,-qrf

            if(smoiold(k).gt.smoisat)then
                 dsmoi=max((smoiold(k)-smoisat)*dz(k),0.)
                 if(k.lt.nzg)then
                        smoiold(k+1)=smoiold(k+1)+dsmoi*vctr2(k+1)
                        vt3di(k+1)=vt3di(k+1)+dsmoi
                 else
                        vt3di(k+1)=vt3di(k+1)+dsmoi
                        runoff=runoff+dsmoi
                 endif
                 smoiold(k)=smoisat
                 if(capflux(k+1).lt.0)then
                    gravflux(k+1)=gravflux(k+1)+capflux(k+1)
                    capflux(k+1)=0.
                 endif
                    gravflux(k+1)=gravflux(k+1)+dsmoi
                    if(gravflux(k+1).gt.0.)then
                           capflux(k+1)=capflux(k+1)+gravflux(k+1)
                           gravflux(k+1)=0.
                    endif
            endif
!if(i.eq.69.and.j.eq.34)write(6,*)'soilflux 2',k,smoiold(k),vt3di(k+1),dsmoi,iwtd,wtd
        enddo



!        do k=nzg,1

!            if(slz(k).lt.-0.30)then
!                  nsoil=soiltxt(1)
!            else
!                  nsoil=soiltxt(2)
!            endif
!            smoicp = soilcp(nsoil)*max(min(exp((vctr4(k)+1.5)/fdepth),1.),0.1)

!             if(smoiold(k).lt.smoicp)then
!                 dsmoi=max((smoicp-smoiold(k))*dz(k),0.)
!                 if(vt3di(k).lt.0.)then
!                      vt3di(k)=vt3di(k)+dsmoi
!                      dsmoi=max(vt3di(k),0.)
!                      vt3di(k)=min(vt3di(k),0.)
!                 endif
!                 smoiold(k+1)=smoiold(k+1)-dsmoi*vctr2(k+1)
!                 vt3di(k+1)=vt3di(k+1)-dsmoi
!                 smoiold(k)=smoicp
!             endif
!        enddo

        k=nzg

            if(slz(k).lt.-0.30)then
                  nsoil=soiltxt(1)
            else
                  nsoil=soiltxt(2)
            endif

            smoicp = soilcp(nsoil)*max(min(exp((vctr4(k)+1.5)/fdepth),1.),0.1)

        if(smoiold(k).lt.smoicp)then
!first reduce soil evaporation from PET
                 dsmoi=max((smoicp-smoiold(k))*dz(k),0.)
             if(vt3di(k+1) .gt. dsmoi)then
                 et_s = max( 0. ,  pet_s - dsmoi*1.e3)
                 smoiold(k) = smoicp
                 vt3di(k+1)=vt3di(k+1)-dsmoi
             else
                 et_s = max( 0. ,  pet_s - max(vt3di(k+1),0.)*1.e3 )
                 vt3di(k+1)=min(vt3di(k+1),0.)
                 smoiold(k) = smoiold(k) + max(vt3di(k+1),0.)/dz(k)
!take water from below
                 dsmoi=max((smoicp-smoiold(k))*dz(k),0.)
                 smoiold(k-1)=smoiold(k-1)-dsmoi*vctr2(k-1)
                 vt3di(k)=vt3di(k)+dsmoi
                 smoiold(k)=smoicp
             endif
       else
           et_s = pet_s
       endif

!then go down all the way to the bottom
                 do k=nzg-1,1,-1
                      if(slz(k).lt.-0.30)then
                          nsoil=soiltxt(1)
                      else
                          nsoil=soiltxt(2)
                      endif

                      smoicp = soilcp(nsoil)*max(min(exp((vctr4(k)+1.5)/fdepth),1.),0.1)
                      if(smoiold(k).lt.smoicp)then
             !take water from below
                        dsmoi=max((smoicp-smoiold(k))*dz(k),0.)
                        if(k.gt.1)smoiold(k-1)=smoiold(k-1)-dsmoi*vctr2(k-1)
                        vt3di(k)=vt3di(k)+dsmoi
                        smoiold(k)=smoicp
                      endif
                 enddo


if(vt3di(1).gt.0.)then
       qrfcorrect = - min(vt3di(1),max(qrf,0.))
!       write(6,*)'too much qrf',i,j,qrf,qrfcorrect,vt3di(1),qlat,wtd
else
       qrfcorrect = 0.
endif


!save rain penetration depth

flux=flux+vt3di

!     do k=1,nzg
!       if(vt3di(k).lt.-1.e-6)then
!            if(pppendepth.gt.slz(k))pppendepth=slz(k)
!            exit
!       endif
!     enddo
IF(freedrain.eq.1)then

!accumulate gravitational drainage
            rech = vt3di(1)
!smoiwtd is now the bucket of water at the bottom, to save the water and put it later into the rivers
            smoiwtd=smoiwtd-vt3di(1)


ENDIF

!now o18 tracer

vt3di(1) = 0.
capflux(1) = 0.
gravflux(1)= 0.

transpo18 = 0.


            do k=2,nzg
                if(capflux(k).lt.0)then
                    gravflux(k)=gravflux(k)+capflux(k)
                    capflux(k)=0.
                endif
                fluxdiff=vt3di(k)-(gravflux(k)+capflux(k))
                if(fluxdiff.gt.0.)then
                     capflux(k)=capflux(k)+fluxdiff
                else
                     gravflux(k)=gravflux(k)+fluxdiff
                endif

            enddo

!calculate tridiagonal matrix elements

     do k=1,nzg-1
 
         bb(k) = 1. + 0.5 * vctr2(k) * transp(k) / smoiold(k)
         rr(k) = o18(k) - 0.5 * vctr2(k) * transp(k) * o18ratio(k)

              bb(k) = bb(k) - 0.5 * vctr2(k) *  gravflux(k) / smoiold(k)
              rr(k) = rr(k) + 0.5 * vctr2(k) *  gravflux(k) * o18ratio(k)
              aa(k) = - 0.5 * vctr2(k) * capflux(k) / smoiold(k-1)
              rr(k) = rr(k) + 0.5 * vctr2(k) * capflux(k) * o18ratio(k-1)

              cc(k) = 0.5 * vctr2(k) * gravflux(k+1) / smoiold(k+1)
              rr(k) = rr(k) - 0.5 * vctr2(k) * gravflux(k+1) * o18ratio(k+1)
              bb(k) = bb(k) + 0.5 * vctr2(k) * capflux(k+1) / smoiold(k)
              rr(k) = rr(k) - 0.5 * vctr2(k) * capflux(k+1) * o18ratio(k)

     enddo


!top boundary

         bb(nzg) = 1. + 0.5 * vctr2(nzg) * transp(nzg) / smoiold(nzg)
         rr(nzg) = o18(nzg) - 0.5 * vctr2(nzg) * transp(nzg) * o18ratio(nzg)

              bb(nzg) = bb(nzg) - 0.5 * vctr2(nzg) * gravflux(nzg) / smoiold(nzg)
              rr(nzg) = rr(nzg) + 0.5 * vctr2(nzg) *  gravflux(nzg) * o18ratio(nzg)
              aa(nzg) = -0.5 * vctr2(nzg) * capflux(nzg) / smoiold(nzg-1)
              rr(nzg) = rr(nzg) + 0.5 * vctr2(nzg) * capflux(nzg) * o18ratio(nzg-1)

         alpha = 1. / (exp( 1137./tempsfc**2. - 0.4156/tempsfc - 0.0020667))

         bb(nzg) = bb(nzg) + 0.5* vctr2(nzg) * (alpha * et_s * 1.e-3) / smoiold(nzg)
         rr(nzg) = rr(nzg) - 0.5 * vctr2(nzg) * (alpha * et_s * 1.e-3) *  o18ratio(nzg)

!         if(runoff.lt.precip *1.e-3 + flood )then
!              rr(nzg) = rr(nzg) + precipo18 * max(precip *1.e-3 + flood  - runoff ,0.) * vctr2(nzg)
         if(vt3di(nzg+1) - et_s *1.e-3 .lt.0.)then
              rr(nzg) = rr(nzg) + precipo18 * max(et_s *1.e-3 - vt3di(nzg+1) ,0.) * vctr2(nzg)
         else
!              bb(nzg) = bb(nzg) + 0.5 * vctr2(nzg) * (runoff - precip *1.e-3 - flood ) / smoiold(nzg)
!              rr(nzg) = rr(nzg) - 0.5 * vctr2(nzg) * (runoff - precip *1.e-3 - flood ) *  o18ratio(nzg)
              bb(nzg) = bb(nzg) + 0.5 * vctr2(nzg) * (vt3di(nzg+1) - et_s *1.e-3 ) / smoiold(nzg)
              rr(nzg) = rr(nzg) - 0.5 * vctr2(nzg) * (vt3di(nzg+1) - et_s *1.e-3 ) *  o18ratio(nzg)
         endif



!solve tridiagonal system and update smoi
!k=40
           o18dz = o18

            call tridag(aa,bb,cc,rr,o18,nzg)

!            o18 = o18dz / dz

      do k=1,nzg
          transpo18 = transpo18 + 0.5 * (o18(k)/smoiold(k) + o18ratio(k)) * transp(k)
          if(o18(k).lt.0.)write(6,*)'O18 less than zero!!!',o18dz(k),o18(k),i,j,k,iwtd-1,vt3di(k),capflux(k),gravflux(k),vt3di(k+1),capflux(k+1),gravflux(k+1),o18ratio(k)*transp(k)*vctr2(k)
          if(o18(k).gt.smoiold(k))write(6,*)'O18 greater than smoi!!!',o18dz(k),o18(k),vt3di(k),vt3di(k+1),smoiold(k),i,j,k
      enddo



!update wtd
call updateshallowwtd(i,j,nzg,freedrain,slz,dz,soiltxt,smoieq,smoiwtd,smoiold,wtd,rech,fdepth)
     do k=1,nzg
     if(wtd.lt.slz(k))exit
     enddo
     iwtd=k

     kwtd=max(iwtd-1,1)
!now lateral flow

!if(i.eq.20.and.j.eq.82)write(6,*)'now qlat',qlat

     qlatlayer=qgw
     if(qrf.gt.0)then
          qgwo18=qlato18-o18ratio(kwtd)*qrf
     else
          qgwo18=qlato18-precipo18*qrf
     endif


!if(i.eq.20.and.j.eq.82)write(6,*)'now qlat',qlat,kwtd,o18(kwtd),qlato18/dz(k)

         if(qgw.gt.0.)then
           do k=max(kwtd-1,1),nzg

            if(slz(k).lt.-0.30)then
                  nsoil=soiltxt(1)
            else
                  nsoil=soiltxt(2)
            endif

             smoisat = slmsts(nsoil)*max(min(exp((vctr4(k)+1.5)/fdepth),1.),0.1)
             dsmoi = (smoisat - smoiold(k)) * dz(k)
                if(qlatlayer.le.dsmoi)then
                    smoiold(k) = smoiold(k) + qlatlayer * vctr2(k)
                    o18frac = qlatlayer/qgw
                    o18frac = min(max(o18frac,0.),1.)
                    o18(k) = o18(k) + o18frac * qgwo18 * vctr2(k)
!if(i.eq.20.and.j.eq.82)write(6,*)'now qlat +',qlatlayer,k,o18(k)
                    qlatflux(k)=qlatflux(k)+qlatlayer
                    exit
                elseif(k.eq.kwtd-1)then
                    smoiold(k) = smoisat
                    o18frac = dsmoi/qgw
                    o18frac = min(max(o18frac,0.),1.)
                    o18(k) = o18(k) + o18frac * qgwo18 * vctr2(k)

                    qlatlayer = qlatlayer - dsmoi
                    qlatflux(k)=qlatflux(k)+dsmoi
!if(i.eq.100.and.j.eq.35)write(6,*)'now qlat +',qlatlayer,k,o18(k),dsmoi,( 1.e6 * (o18(k)/smoiold(k)) / 2005.2 - 1. ) * 1.e3

                 else
                     smoiold(k) = smoiold(k) + qlatlayer * vctr2(k)
                     o18frac = qlatlayer/qgw
                     o18frac = min(max(o18frac,0.),1.)
                     o18(k) = o18(k) + o18frac * qgwo18 * vctr2(k)
                     o18ratio(k)=o18(k)/smoiold(k)
                     !after mixing, take out what is over saturation
                     smoiold(k) = smoisat
                     o18(k) = smoisat*o18ratio(k)

                     qlatlayer = qlatlayer - dsmoi
                     qgwo18 = o18ratio(k)*qlatlayer
                     qgw=qlatlayer
                     qlatflux(k)=qlatflux(k)+dsmoi

!if(i.eq.100.and.j.eq.35)write(6,*)'now qlat +',qlatlayer,k,o18(k),dsmoi,( 1.e6 * (o18(k)/smoiold(k)) / 2005.2 - 1. ) * 1.e3
                    if(k.eq.nzg)then
                        runoff = runoff + qlatlayer
                        exit
                    endif
                endif
            enddo
         elseif(qgw.lt.0.)then
            do k=kwtd,1,-1
              dsmoi = max( (smoiold(k) - smoieq(k)) * dz(k) , 0.)
              if(k.eq.1)then
                    nsoil=soiltxt(2)
                    smoicp = soilcp(nsoil)*max(min(exp((vctr4(k)+1.5)/fdepth),1.),0.1)
                    dsmoi = max( (smoiold(k) - smoicp) * dz(k) , 0.)
              endif
              if(-qlatlayer.le.dsmoi)then
                    smoiold(k) = smoiold(k) + qlatlayer * vctr2(k)
                    o18frac = qlatlayer/qgw
                    o18frac = min(max(o18frac,0.),1.)
                    o18out = -o18frac * qgwo18 
                    if(o18(k)*dz(k).lt.o18out.and.k.gt.1)then !take part from the layer below
                         o18tot=o18(k)*dz(k)+o18(k-1)*dz(k-1)
                         o18frac = o18(k)*dz(k)/o18tot
                         o18(k) = o18(k) - o18frac*o18out*vctr2(k)
                         o18(k-1) = o18(k-1) - (1.-o18frac)*o18out*vctr2(k-1)
                    else
                       o18(k) = o18(k) - o18out * vctr2(k)
                    endif
                    qlatflux(k)=qlatflux(k)+qlatlayer
!if(i.eq.20.and.j.eq.82)write(6,*)'now qlat -',qlatlayer,k,o18(k),dsmoi,o18frac
                   exit
              else
                    qlatlayer = qlatlayer  + dsmoi
                    smoiold(k) = smoiold(k) - dsmoi * vctr2(k)

                    o18frac = -dsmoi/qgw
                    o18frac = min(max(o18frac,0.),1.)
                    o18(k) = o18(k) + o18frac * qgwo18 * vctr2(k)

                    qlatflux(k)=qlatflux(k)+dsmoi
!if(i.eq.20.and.j.eq.82)write(6,*)'now qlat -',qlatlayer,k,o18(k),dsmoi,o18frac
                    if(k.eq.1)then
                        qrfcorrect = qrfcorrect  - qlatlayer
                        exit
                    endif
              endif
            enddo
          endif



!          if(iwtd.eq.1)o18(1) = o18(1) + o18ratio (1) * qgw * vctr2(1)

      do k=1,nzg
!      if(i.eq.100.and.j.eq.35.and.k.gt.35)write(6,*)'mirar o18 despues',i,j,k,o18(k),o18(k)/smoiold(k) &
!          , ( 1.e6 * (o18(k)/smoiold(k)) / 2005.2 - 1. ) * 1.e3 
          if(o18(k).lt.0.)write(6,*)'O18 less than zero!!!',o18(k),i,j,k,iwtd-1,qlat,qlato18,qrf
          if(o18(k).gt.smoiold(k))write(6,*)'O18 greater than smoi!!!',o18(k),smoiold(k),i,j,k,iwtd-1,qlato18,qrf
      enddo

          o18 = max(o18,0.)

!          o18ratio = o18 / smoiold

          smoi=smoiold


end subroutine soilfluxes
!**********************************************************************************************
SUBROUTINE UPDATESHALLOWWTD(i,j,nzg,freedrain,slz,dz,soiltxt,smoieq,smoiwtd,smoi,wtd,rech,fdepth)

integer :: nzg,freedrain,nsoil,nsoil1,k,iwtd,kwtd,i,j,flag
real, dimension(nzg+1) :: slz
real, dimension(nzg) :: dz,vctr4
real, dimension(nzg) :: smoieq,smoi
integer, dimension(2) :: soiltxt
real :: wtd,wtdold,wgpmid,rech,smoiwtd,dzup,smoieqwtd,fdepth,smoisat

rech=0.
!flag=0

         do k=1,nzg
            vctr4(k) = 0.5 * (slz(k) + slz(k+1))
         enddo


     do k=1,nzg
!     if(wtd+1.e-6.lt.slz(k))exit
     if(wtd.lt.slz(k))exit
     enddo
     iwtd=k


DO 
flag=0

        kwtd=iwtd-1
        if(kwtd.gt.0)then    !wtd in the resolved layers
           wtdold=wtd

           if(slz(kwtd).lt.-0.30)then
                 nsoil=soiltxt(1)
           else
                 nsoil=soiltxt(2)
           endif

           if(kwtd.gt.1)then
               smoisat = slmsts(nsoil)*max(min(exp((vctr4(kwtd-1)+1.5)/fdepth),1.),0.1)
               if(wtd.lt.slz(kwtd)+0.01.and.smoi(kwtd-1).lt.smoisat)flag=1

           endif

           smoisat = slmsts(nsoil)*max(min(exp((vctr4(kwtd)+1.5)/fdepth),1.),0.1)

           if(smoi(kwtd).gt.smoieq(kwtd).and.flag.eq.0)then

               if(smoi(kwtd).eq.smoisat)then !wtd went to the layer above
                      wtd=slz(iwtd)
                      rech=(wtdold-wtd) * (smoisat-smoieq(kwtd))
                      iwtd=iwtd+1
                      kwtd=kwtd+1
                   if(kwtd.le.nzg)then
                      if(smoi(kwtd).gt.smoieq(kwtd))then
                      wtdold=wtd

                      if(slz(kwtd).lt.-0.30)then
                           nsoil=soiltxt(1)
                      else
                           nsoil=soiltxt(2)
                      endif

                      smoisat = slmsts(nsoil)*max(min(exp((vctr4(kwtd)+1.5)/fdepth),1.),0.1)
                      wtd = min( ( smoi(kwtd)*dz(kwtd) &
                        - smoieq(kwtd)*slz(iwtd) + smoisat*slz(kwtd) ) / &
                        ( smoisat-smoieq(kwtd) ), slz(iwtd))
                      rech=rech+(wtdold-wtd) * (smoisat-smoieq(kwtd))
                      endif
                    else
                      exit
                   endif
               else  !wtd stays in the layer
                      wtd = min( ( smoi(kwtd)*dz(kwtd) &
                        - smoieq(kwtd)*slz(iwtd) + smoisat*slz(kwtd) ) / &
                        ( smoisat-smoieq(kwtd) ), slz(iwtd))
                      rech=(wtdold-wtd) * (smoisat-smoieq(kwtd))
                      exit
               endif

           else    !wtd has gone down to the layer below
               wtd=slz(kwtd)
               rech=(wtdold-wtd) * (smoisat-smoieq(kwtd))
               kwtd=kwtd-1
               iwtd=iwtd-1
!wtd crossed to the layer below. Now adjust it there
               if(kwtd.ge.1)then
                   wtdold=wtd

                   if(slz(kwtd).lt.-0.30)then
                         nsoil=soiltxt(1)
                   else
                         nsoil=soiltxt(2)
                   endif

                   smoisat = slmsts(nsoil)*max(min(exp((vctr4(kwtd)+1.5)/fdepth),1.),0.1)

                   if(smoi(kwtd).gt.smoieq(kwtd))then
                     wtd = min( ( smoi(kwtd)*dz(kwtd) &
                           - smoieq(kwtd)*slz(iwtd) + smoisat*slz(kwtd) ) / &
                           ( smoisat-smoieq(kwtd) ) , slz(iwtd) )
                     rech = rech + (wtdold-wtd) * &
                                 (smoisat-smoieq(kwtd))    
                     exit
                   else
                     wtd=slz(kwtd)
                     rech = rech + (wtdold-wtd) * &
                                 (smoisat-smoieq(kwtd))
                   endif
                 else
                   exit
                endif

            endif

         endif

ENDDO

if(wtd.lt.slz(1))write(6,*)'problem with wtd',wtd,i,j

end subroutine updateshallowwtd

!     ******************************************************************

subroutine UPDATEWTDQLAT(nzg,slz,dz,wtd,qspring,qlat,smoi,smoieq,soiltextures,smoiwtd,qlatflux,fdepth)
implicit none
integer :: nzg,iwtd,kwtd,nsoil,nsoil1,k,k1
real , dimension(nzg+1) :: slz
real , dimension(0:nzg+1) :: qlatflux
real , dimension(nzg) :: dz,vctr4
real :: wtd,qspring,wtdold,qlat,totwater,smoiwtd,maxwatup,maxwatdw,wgpmid,syielddw,dzup,tempk,fracliq,smoieqwtd,fdepth,smoisat
real, dimension(nzg) :: smoi,smoieq

integer, dimension(2) :: soiltextures
integer, dimension(nzg) :: soiltxt

         do k=1,nzg
            vctr4(k) = 0.5 * (slz(k) + slz(k+1))
         enddo

where(slz.lt.-0.3)
     soiltxt=soiltextures(1)
elsewhere
     soiltxt=soiltextures(2)
endwhere

qspring=0.
totwater=qlat

iwtd=1

!case 1: totwater > 0 (water table going up):
IF(totwater.gt.0.)then



            do k=2,nzg
              if(wtd.lt.slz(k))exit
            enddo
            iwtd=k
            kwtd=iwtd-1
            nsoil=soiltxt(kwtd)
            smoisat = slmsts(nsoil)*max(min(exp((vctr4(kwtd)+1.5)/fdepth),1.),0.1)
!max water that fits in the layer
            maxwatup=dz(kwtd)*(smoisat-smoi(kwtd))

            if(totwater.le.maxwatup)then
               smoi(kwtd) = smoi(kwtd) + totwater / dz(kwtd)
               qlatflux(kwtd) = qlatflux(kwtd) + totwater
               smoi(kwtd) = min(smoi(kwtd),smoisat)
               if(smoi(kwtd).gt.smoieq(kwtd))wtd = min ( ( smoi(kwtd)*dz(kwtd) &
                 - smoieq(kwtd)*slz(iwtd) + smoisat*slz(kwtd) ) / &
                     ( smoisat-smoieq(kwtd) ) , slz(iwtd) )
               totwater=0.
            else   !water enough to saturate the layer
              smoi(kwtd) = smoisat
              qlatflux(kwtd) = qlatflux(kwtd) + maxwatup
              totwater=totwater-maxwatup
              k1=iwtd
              do k=k1,nzg+1
                 wtd = slz(k)
                 iwtd=k+1
                 if(k.eq.nzg+1)exit
                 nsoil=soiltxt(k)
                 smoisat =slmsts(nsoil)*max(min(exp((vctr4(k)+1.5)/fdepth),1.),0.1)
                 maxwatup=dz(k)*(smoisat-smoi(k))
                 if(totwater.le.maxwatup)then
                   smoi(k) = smoi(k) + totwater / dz(k)
                   qlatflux(k) = qlatflux(k) + totwater
                   smoi(k) = min(smoi(k),smoisat)
                   if(smoi(k).gt.smoieq(k))wtd = min ( ( smoi(k)*dz(k) &
                     - smoieq(k)*slz(iwtd) + smoisat*slz(k) ) / &
                     ( smoisat-smoieq(k) ) , slz(iwtd) )
                   totwater=0.
                   exit
                 else
                    smoi(k) = smoisat
                    qlatflux(k) = qlatflux(k) + maxwatup
                    totwater=totwater-maxwatup
                 endif

              enddo

            endif


!water springing at the surface
        qspring=totwater

!case 2: totwater < 0 (water table going down):
ELSEIF(totwater.lt.0.)then



           do k=2,nzg
               if(wtd.lt.slz(k))exit
            enddo
            iwtd=k

               k1=iwtd-1
               do kwtd=k1,1,-1

                  nsoil=soiltxt(kwtd)
                  smoisat = slmsts(nsoil)*max(min(exp((vctr4(kwtd)+1.5)/fdepth),1.),0.1)

!max water that the layer can yield
                  maxwatdw=dz(kwtd)*(smoi(kwtd)-smoieq(kwtd))

                  if(-totwater.le.maxwatdw)then
                        smoi(kwtd) = smoi(kwtd) + totwater / dz(kwtd)
                        qlatflux(kwtd) = qlatflux(kwtd) + totwater
                        if(smoi(kwtd).gt.smoieq(kwtd))then
                              wtd = ( smoi(kwtd)*dz(kwtd) &
                                 - smoieq(kwtd)*slz(iwtd) + smoisat*slz(kwtd) ) / &
                                 ( smoisat-smoieq(kwtd) )
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
                            qlatflux(kwtd) = qlatflux(kwtd) + maxwatdw
                            totwater = totwater + maxwatdw
                         endif
                   endif

                enddo

               if(iwtd.eq.1.and.totwater.lt.0.)then
                  nsoil=soiltxt(1)
                  smoisat = slmsts(nsoil)*max(min(exp((vctr4(1)+1.5)/fdepth),1.),0.1)

                       smoi(1) = smoi(1) + totwater / dz(1)
                       qlatflux(1) = qlatflux(1) + totwater
                       wtd = max( ( smoi(1)*dz(1) &
                           - smoieq(1)*slz(2) + smoisat*slz(1) ) / &
                            ( smoisat-smoieq(1) ) , slz(1) )


                endif



          qspring=0.

ENDIF


end subroutine updatewtdqlat

!**********************************************************************************************
SUBROUTINE tridag(a,b,c,r,u,n)
      INTEGER n,NMAX
      REAL a(n),b(n),c(n),r(n),u(n)
      PARAMETER (NMAX=500)
      INTEGER j
      REAL bet,gam(NMAX)
      if(b(1).eq.0.)pause 'tridag: rewrite equations'
      bet=b(1)
      u(1)=r(1)/bet
      do 11 j=2,n
        gam(j)=c(j-1)/bet
        bet=b(j)-a(j)*gam(j)
        if(bet.eq.0.)write(6,*)j,b(j),a(j),gam(j)
        if(bet.eq.0.)pause 'tridag failed'
        u(j)=(r(j)-a(j)*u(j-1))/bet
11    continue
      do 12 j=n-1,1,-1
        u(j)=u(j)-gam(j+1)*u(j+1)
12    continue

end subroutine tridag

!**********************************************************************************************
SUBROUTINE init_soil_param(fieldcp,nzg)

real, parameter :: potwilt=-153. !matric potential at wilting point
integer :: nsoil,k,irec,nzg
real, dimension(nzg,nstyp) :: fieldcp


!define soilcp, the wilting point in terms of matric potential
   do nsoil=1,nstyp
         slwilt(nsoil)= slmsts(nsoil) * ( slpots(nsoil)/potwilt )**(1./slbs(nsoil))
   enddo

end subroutine init_soil_param

!**********************************************************************************************

FUNCTION khyd(smoi,nsoil)
integer :: nsoil
real :: khyd,smoi

khyd = slcons(nsoil) * (smoi  / slmsts(nsoil)) ** (2. * slbs(nsoil) + 3.)

END FUNCTION khyd

END MODULE MODULE_ROOTDEPTH
