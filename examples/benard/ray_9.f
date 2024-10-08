c-----------------------------------------------------------------------
      subroutine rayleigh_const

      include 'SIZE'
      include 'INPUT'

      common /rayleigh_r/ rapr,ta2pr
      common /rayleigh_c/ Ra1,Ra2,Ra3,Pr,Ta2,Ek1,Ek2,Ek3,sstol,Rc

      Pr  = param(2)	! Pr=1
      eps = param(75)
      Rc  = param(76)
      Ta2 = param(77)
      Ra  = Rc*(1.+eps)

      eps2= param(121)
      eps3= param(122)
      Ra1 = Ra
      Ra2 = Rc*(1.+eps2)	! check for monotonicity & non-zero?
      Ra3 = Rc*(1.+eps3)
      Ek1 = 0.
      Ek2 = 0.
      Ek3 = 0.
      sstol = param(123)	! 1.e-8	 	! steady state tolerance on Ek time derivative

      if (sstol.gt.0.0.and.abs(Ra1-Ra2).lt.1.e-7
     $                .and.abs(Ra2-Ra3).lt.1.e-7.and.nid.eq.0) then
         write (6,*) ' Equal epsilons : ',eps,eps2,eps3
         call exitt
      endif

      rapr    = ra*pr
      ta2pr   = ta2*pr

      cond    = param(8)			! check for Pr = 1
      if (abs(cond-Pr).gt.1.e-7.and.nid.eq.0)
     $call exitti(" rayleigh_const error: p8 - p1 = $",cond - param(2))

      if (nid.eq.0) write(6,1) Ra,Pr,Ta2,eps,Rc,sqrt(Ta2)	! Ro?
    1 format(5x,'Ra = ',1pg11.4,3x,'Pr = ',g11.4,3x,'Ta^2 = ',g11.4,
     $       5x,'eps = ', g11.4,3x,'Rc = ',g11.4,5x,'Ta = ',  g11.4)

      return
      end
c-----------------------------------------------------------------------
      subroutine uservp (ix,iy,iz,ieg)
      include 'SIZE'
      include 'TOTAL'
      include 'NEKUSE'

      udiff  = 0
      utrans = 0

      return
      end
c-----------------------------------------------------------------------
      subroutine userf  (ix,iy,iz,ieg)
      include 'SIZE'
      include 'TOTAL'
      include 'NEKUSE'

      common /rayleigh_r/ rapr,ta2pr

      buoy = temp*rapr

      if (if3d) then
         ffx  =   uy*Ta2Pr
         ffy  = - ux*Ta2Pr
         ffz  = buoy
      elseif (ifaxis) then
         ffx  = -buoy
         ffy  =  0.
      else
         ffx  = 0.
         ffy  = buoy
      endif
c     write(6,*) ffy,temp,rapr,'ray',ieg

      return
      end
c-----------------------------------------------------------------------
      subroutine userq  (ix,iy,iz,ieg)
      include 'SIZE'
      include 'TOTAL'
      include 'NEKUSE'

      qvol   = 0.0
      source = 0.0
      return
      end
c-----------------------------------------------------------------------
      subroutine userbc (ix,iy,iz,iside,ieg)
      include 'SIZE'
      include 'TSTEP'
      include 'INPUT'
      include 'NEKUSE'
      common /rayleigh_r/ rapr,ta2pr

      ux=0.
      uy=0.
      uz=0.

      temp=0.  !     Temp = 0 on top, 1 on bottom

      if (if3d) then
         temp = 1-z
      elseif (ifaxis) then  !      domain is on interval x in [-1,0]
         temp = 1.+x
      else                  ! 2D:  domain is on interval y in [0,1]
         temp = 1.-y
      endif


      return
      end
c-----------------------------------------------------------------------
      subroutine useric (ix,iy,iz,ieg)
      include 'SIZE'
      include 'TOTAL'
      include 'NEKUSE'
      integer idum
      save    idum
      data    idum /99/

      ran = 2.e7*(ieg+x*sin(y)) + 1.e6*ix*iy + 1.e7*ix 
      ran = 1.e9*sin(ran)
      ran = 1.e9*sin(ran)
      ran = cos(ran)
      ran = ran1(idum)
      amp = .001

      temp = 1-y + ran*amp*(1-y)*y*x*(9-x)	! 2D & xmax=9

      ux=0.0
      uy=0.0
      uz=0.0

      return
      end
c-----------------------------------------------------------------------
      subroutine usrdat
      return
      end
c-----------------------------------------------------------------------
      subroutine usrdat3
      return
      end
c-----------------------------------------------------------------------
      subroutine usrdat2
      include 'SIZE'
      include 'TOTAL'

      common /rayleigh_c/ Ra1,Ra2,Ra3,Prnum,Ta2,Ek1,Ek2,Ek3,sstol,Rc ! for Rc

      call rayleigh_const


c     param(66) = 4
c     param(67) = 4

      ntot = nx1*ny1*nz1*nelv	! nelv as in rescale_x
      xmin = glmin(xm1,ntot)
      xmax = glmax(xm1,ntot)
      xlen = param(120)
      xmxn = xmin + xlen
      call rescale_x(xm1,xmin,xmxn)
      if (nid.eq.0) write (6,10) xmin,xmax,xmin,xmxn,2.*pi/xlen,Rc
   10 format(" X is rescaled from (",1pe15.7," , ",e15.7,") to (",e15.7
     $       ," , ",e15.7,") so K_max = ",e15.7," for the target Ra = "
     $             ,e15.7)

      return
      end
c-----------------------------------------------------------------------
      subroutine userchk
      include 'SIZE'
      include 'TOTAL'
      common /scrns/ tz(lx1*ly1*lz1*lelt)

      real Ek0,Ek
      save Ek0,Ek	! for growth?


      n    = nx1*ny1*nz1*nelv
      Ek0  = Ek
      Ek   = (glsc3(vx,vx,bm1,n)
     $     +  glsc3(vy,vy,bm1,n))/volvm1/2.
      

      ifxyo = .true.  ! For VisIt
      if (istep.gt.iostep) ifxyo = .false.
      if (istep.le.1) then
         do i=1,n
            tz(i) = t(i,1,1,1,1) - (1. - ym1(i,1,1,1))	! 2D  ? IC?
         enddo
         call outpost(vx,vy,vz,pr,tz,'   ')
      endif

      call runtimeavg(aEk,Ek,1,1,1,'E_k  ')

      if (istep.gt.1.and.Ek0.ne.0.) then	!?skip w/ sign change?
         ratio   =   Ek/Ek0
         grwtEk  = log(ratio)/dt
         call runtimeavg(agEk,grwtEk,2,100,1,'grEk ')	! skip transient ~100 steps for averaged growth rate
      endif

      call rayleigh_fit(Ek,.true.)		! Ra_crit fit
 
      return
      end
c-----------------------------------------------------------------------
      subroutine rayleigh_fit(Ekin,iffin)
c
c     for steady state tolerence sstol>0 and istep>initskip tests
c     solutions for convergence, stores converged value of Ek for the
c     fitting of Ra_critical, outpost converged solution for
c     iffin=.true., adjusts Rayleigh number factors Pr*Ra and Pr*Ta^2,
c     and prints Ra_critical Raf fitted from Ek1 & Ek2 along w/ assumed
c     one Rc, error Raer and deviation of Ek3 from the fitted one.
c
c     Note: sync call to runtimeavg w/ other calls to it
c
      include 'SIZE'
      include 'TOTAL'

      logical iffin

      common /rayleigh_r/ rapr,ta2pr
      common /rayleigh_c/ Ra1,Ra2,Ra3,Prnum,Ta2,Ek1,Ek2,Ek3,sstol,Rc

      real Ek,Ek0,Ekp
      save Ek,Ek0,Ekp
      data Ek,Ek0,Ekp /3*0.0/


      initskip = 100	! steps to skip before RBI kinks in to miss the 1st Ek minimum

      Ekp = Ek0						! for time derivative
      Ek0 = Ek
      Ek  = Ekin
      if (sstol.gt.0.0.and.istep.gt.initskip) then	! otherwise return
         derivEk = 0.5*(3.*Ek - 4.*Ek0 + Ekp)/dt
         call runtimeavg(adEk,derivEk,3,2,1,'drvEk')
         if (abs(Ek).gt.1.e-15) then
            derivlog = abs(derivEk/Ek)
            if (derivlog.lt.sstol) then			! store steady state Ek w/ Ra
               if (Ek1.eq.0.) then
                  Ek1   = Ek
                  Ra    = Ra2
                  vm    = 0. 		! if Ek<0
                  if (Ek.gt.0.)  vm  =  sqrt(2.*Ek)
                  if (iffin) call outpost(vx,vy,vz,pr,t,'fin') 
                  if (nid.eq.0) write (6,10) istep,time,Ek,vm,Ra1,'ra1'
               else if (Ek2.eq.0.) then
                  Ek2   = Ek
                  Ra    = Ra3
                  vm    = 0. 		! if Ek<0
                  if (Ek.gt.0.)  vm  =  sqrt(2.*Ek)
                  if (iffin) call outpost(vx,vy,vz,pr,t,'fin') 
                  if (nid.eq.0) write (6,10) istep,time,Ek,vm,Ra2,'ra2'
               else
                  Ek3   = Ek
                  vm    = 0. 		! if Ek<0
                  if (Ek.gt.0.)  vm  =  sqrt(2.*Ek)
                  if (iffin) call outpost(vx,vy,vz,pr,t,'fin') 
                  if (nid.eq.0) write (6,10) istep,time,Ek,vm,Ra3,'ra3'
c Ra_crit_12 fit
                  coefa =  (Ek1 - Ek2)/(Ra1 - Ra2) ! Ek = a*(Ra-Rc) + b
                  coefb = (-Ek1*(Ra2 - Rc) + Ek2*(Ra1 - Rc))/(Ra1 - Ra2)
                  if (abs(coefa).gt.1.e-15) then
                     Racf  = Rc - coefb/coefa		! Ra_crit from linear fit of Ek1,2
                     Raer = abs((Racf-Rc)/Rc)		! Error in Ra_crit
                     Ekc  = coefa*(Racf - Rc) + coefb
                     vm   = 0.		!  if Ekc<0
                     if (Ekc.gt.0.) vm = sqrt(2.*Ekc)
                     if (nid.eq.0)
     $                         write(6,10) istep,time,Ekc,vm,Racf,'rac'
                  endif
c Ra_crit_23 fit
                  coefa =  (Ek2 - Ek3)/(Ra2 - Ra3) ! Ek = a*(Ra-Rc) + b
                  coefb = (-Ek2*(Ra3 - Rc) + Ek3*(Ra2 - Rc))/(Ra2 - Ra3)
                  if (abs(coefa).gt.1.e-15) then
                     Rac3  = Rc - coefb/coefa		! Ra_crit from linear fit of Ek2,3
                     Rae3 = abs((Rac3-Rc)/Rc)		! Error in Ra_crit
                  endif
c Rc accuracy
                  if (nid.eq.0) write(6,20) Rc,Racf,Rac3,Raer,Rae3
                  istep = nsteps	! exit
               endif
c adjust Ra
               rapr     =  Ra*Prnum			! Ra factors to adjust
               ta2pr    = Ta2*Prnum
            endif
         endif
      endif
   10 format(i8,1p4e15.7," converged_",a3)
   20 format(1p5e15.7," Rc Ra_crit_12 23 Rac_accuracy_12 23 ")
 
      return
      end
c-----------------------------------------------------------------------
      subroutine runtimeavg(ay,y,j,istep1,ipostep,s5)
c
c     Computes, stores and for ipostep!=0 prints runtime averages
c     of j-quantity y (along w/ y itself unless ipostep<0)
c     with j + 'rtavg_' + (unique) s5 every ipostep for istep>=istep1
c
      include 'SIZE'			! for nid & TSTEP
      include 'TSTEP'			! for istep & time (or TOTAL)
      parameter (lymax=99)		! max of averages to store
      character*5  s5			! unique string to append to 'rtavg_'
      character*14 s14			! i3 + 'rtavg_' + s5
      real         a  (lymax)		! run time average
      character*5  as5(lymax)		! j's strings s5
      save         a,             as5
      data         a  /lymax*0./, as5 /lymax*'     '/

      if (nid.eq.0.and.istep.ge.istep1) then	! otherwsie skip istep
c---
      if (istep1.lt.0) then
         istep1 = 0
         write(6,*) 'Warning:  istep1<0 in runtimeavg -- resetting to 0'
      endif
      if (as5(j).ne.s5.and.as5(j).ne.'     ') then	! check for unique j & s5
         write(6,10) j,s5,as5(j)
         call exitt
      endif

      iistep = istep - istep1 + 1
      if (iistep.gt.1) then			! a_ii = (1-1/ii)*a_ii-1 + 1/ii*y_ii
         wy = 1./iistep
         wa = 1. - wy
         ay = wy*y + wa*a(j)			! runtime average a_ii
      else if (iistep.eq.1) then		! skip istep<istep1
         ay = y
         as5(j) = s5				! check for uniqueness
      endif
      a(j) = ay

      if (ipostep.ne.0.and.mod(istep,iabs(ipostep)).eq.0) then		! printout
         if (ipostep.lt.0) then 
            write (6,20) istep,time,ay,  j,s5
         else
            write (6,30) istep,time,ay,y,j,s5
         endif
      endif
c---
      endif

   10 format('Wrong j or s5 in runtimeavg : ',i3,x,a5,x,a5)
   20 format(i8,1p2e16.8,i3,'rtavg_',a5)
   30 format(i8,1p3e16.8,i3,'rtavg_',a5)
c
      return
      end
c-----------------------------------------------------------------------

c automatically added by makenek
      subroutine usrsetvert(glo_num,nel,nx,ny,nz) ! to modify glo_num
      integer*8 glo_num(1)

      return
      end

c automatically added by makenek
      subroutine userqtl

      call userqtl_scig

      return
      end
